// SPDX-License-Identifier: GPL-2.0+
/*
 * The panel: the early framebuffer console and the DM video driver.
 *
 * The ABL continuous-splash display pipeline keeps scanning out the 1800x2880
 * XRGB8888 (a8r8g8b8) framebuffer at 0xb8000000 (stride 7200 bytes), so U-Boot
 * can draw on the panel with no display bring-up of its own. This file provides:
 *
 * 1. A 16x32 bitmap renderer hooked into the pre-DEVINIT console path
 *    (CONFIG_LIUQIN_EARLY_VIDEO), so every U-Boot printf() from the first
 *    console line onwards is also drawn to the screen with the compiled-in
 *    Terminus 16x32 font (CONFIG_VIDEO_FONT_16X32, the same font the downstream
 *    kernel uses on this 300ppi panel). All output carries a
 *    "LIUQIN-UBOOT: " prefix.
 *
 * 2. A DM video driver that reuses the ABL framebuffer so the regular
 *    vidconsole continues rendering to it after driver-model init.
 *
 * There is no wired UART on this board, so this is the log that matters: the
 * first line has to be visible, and nothing here may need any other driver.
 */

#include <cpu_func.h>
#include <dm.h>
#include <dm/device-internal.h>
#include <dm/root.h>
#include <dm/uclass.h>
#include <linux/kernel.h>
#include <video.h>
#include <video_console.h>
#include <video_font.h>		/* fonts[], CONFIG_VIDEO_FONT_16X32 data */

#include "liuqin.h"

#define LIUQIN_FB_BASE		0xb8000000UL
#define LIUQIN_FB_WIDTH		1800
#define LIUQIN_FB_HEIGHT	2880
#define LIUQIN_FB_STRIDE	7200	/* bytes per scanline */
#define LIUQIN_FB_SIZE		(LIUQIN_FB_STRIDE * LIUQIN_FB_HEIGHT)

/*
 * The panel scans out a8r8g8b8/x8r8g8b8 with the alpha byte opaque, the same
 * colours the working mainline earlycon-simplefb driver writes.
 */
#define LIUQIN_FB_WHITE		0xffffffffU
#define LIUQIN_FB_BLACK		0xff000000U

#if CONFIG_IS_ENABLED(LIUQIN_EARLY_VIDEO)

static u32 *const early_fb = (u32 *)LIUQIN_FB_BASE;

static struct video_fontdata *early_font;
static int early_cols;		/* chars per line */
static int early_rows;		/* lines per screen */
static int early_x, early_y;	/* current cell */
static bool early_sol = true;	/* at start of line, prefix pending */
static int early_esc;		/* inside an ANSI escape sequence (0/1/2) */

static void early_select_font(void)
{
	int i;

	/* Prefer the 16x32 font, fall back to whatever is compiled in. */
	for (i = 0; fonts[i].width; i++) {
		if (fonts[i].width == 16 && fonts[i].height == 32) {
			early_font = &fonts[i];
			break;
		}
	}
	if (!early_font && fonts[0].width)
		early_font = &fonts[0];
	if (!early_font)
		return;

	early_cols = LIUQIN_FB_WIDTH / early_font->width;
	early_rows = LIUQIN_FB_HEIGHT / early_font->height;
}

static void early_draw_char(int col, int row, u8 ch)
{
	const u8 *glyph = early_font->video_fontdata +
			  ch * early_font->char_pixel_bytes;
	u32 *dst = early_fb + row * early_font->height *
				(LIUQIN_FB_STRIDE / 4) + col * early_font->width;
	int r;

	for (r = 0; r < early_font->height; r++) {
		const u8 *line = glyph + r * early_font->byte_width;
		u32 *px = dst + r * (LIUQIN_FB_STRIDE / 4);
		int c;

		for (c = 0; c < early_font->width; c++) {
			bool on = line[c >> 3] & (0x80 >> (c & 7));

			px[c] = on ? LIUQIN_FB_WHITE : LIUQIN_FB_BLACK;
		}
	}

	/*
	 * The scanout engine reads DRAM directly: push the glyph out of the data
	 * cache so the panel sees it even while U-Boot keeps running.
	 */
	flush_dcache_range((ulong)dst,
			   (ulong)dst +
			   (early_font->height - 1) * LIUQIN_FB_STRIDE +
			   early_font->width * 4);
}

/*
 * Wrapping restarts at the top with a wiped screen instead of scrolling:
 * scrolling reads back ~20 MiB per line, which on this panel looks exactly like
 * a hang. This mirrors the mainline earlycon-simplefb driver.
 */
static void early_wrap(void)
{
	u32 *p = early_fb;
	u32 total = (LIUQIN_FB_STRIDE / 4) * LIUQIN_FB_HEIGHT;
	u32 i;

	for (i = 0; i < total; i++)
		*p++ = LIUQIN_FB_BLACK;
	flush_dcache_range((ulong)early_fb, (ulong)early_fb + LIUQIN_FB_SIZE);

	early_x = 0;
	early_y = 0;
	early_sol = true;
}

static void early_newline(void)
{
	early_x = 0;
	early_sol = true;
	if (++early_y >= early_rows)
		early_wrap();
}

static void early_putc(char c)
{
	u8 ch = (u8)c;
	const char *p;

	if (!early_font)
		return;

	if (early_esc) {
		/* Swallow ANSI escape sequences (ESC [ ... final byte). */
		if (early_esc == 1 && ch == '[')
			early_esc = 2;
		else if (early_esc == 2 && ch >= '@' && ch <= '~')
			early_esc = 0;
		else if (early_esc == 1)
			early_esc = 0;
		return;
	}
	if (ch == 0x1b) {
		early_esc = 1;
		return;
	}

	switch (ch) {
	case '\r':
		early_x = 0;
		return;
	case '\n':
		early_newline();
		return;
	case '\t':
		early_x = (early_x + 8) & ~7;
		if (early_x >= early_cols)
			early_newline();
		return;
	}

	if (ch < 0x20 || ch > 0x7e)
		ch = '.';

	if (early_sol) {
		early_sol = false;
		for (p = LIUQIN_PREFIX; *p; p++) {
			early_draw_char(early_x, early_y, *p);
			if (++early_x >= early_cols)
				early_newline();
		}
	}

	early_draw_char(early_x, early_y, ch);
	if (++early_x >= early_cols)
		early_newline();
}

/*
 * Called from common/console.c for every character sent before the regular
 * console devices take over. This is the only log channel on liuqin (no wired
 * serial), so draw everything on the panel.
 */
void board_pre_console_putc(int ch)
{
	if (!early_font)
		early_select_font();
	early_putc((char)ch);
}

/*
 * Hand the screen over to the vidconsole. Called from console_init_r() just
 * before the pre-console buffer is replayed through stdio: wipe the text the
 * early renderer drew and rewind the vidconsole cursor, so the replay is the
 * only thing written to the panel. Trying to continue *below* the early text
 * instead has proven unreliable (the vidconsole still overwrote it), and two
 * writers on one framebuffer make the log unreadable.
 */
void board_pre_console_flush(void)
{
	struct udevice *dev;
	struct vidconsole_priv *priv;

	if (!early_font)
		return;

	early_wrap();	/* wipe the framebuffer, reset the early cursor */

	if (uclass_get_device(UCLASS_VIDEO_CONSOLE, 0, &dev))
		return;

	priv = dev_get_uclass_priv(dev);
	priv->ycur = 0;
	priv->xcur_frac = priv->xstart_frac;
}

#endif /* CONFIG_LIUQIN_EARLY_VIDEO */

/* Bind the font the early renderer picked, so both write the same glyphs. */
void liuqin_early_video_init(void)
{
#if CONFIG_IS_ENABLED(LIUQIN_EARLY_VIDEO)
	early_select_font();
#endif
}

/*
 * DM video driver: reuse the ABL framebuffer as-is; the display pipeline is
 * already scanning it out, no hardware setup required.
 */
static int liuqin_video_probe(struct udevice *dev)
{
	struct video_priv *priv = dev_get_uclass_priv(dev);

	priv->xsize = LIUQIN_FB_WIDTH;
	priv->ysize = LIUQIN_FB_HEIGHT;
	priv->line_length = LIUQIN_FB_STRIDE;
	priv->bpix = VIDEO_BPP32;
	priv->format = VIDEO_X8R8G8B8;
	/* Force the 16x32 font in the vidconsole probe path. */
	priv->font_size = 32;
	video_set_flush_dcache(dev, true);

	return 0;
}

static int liuqin_video_bind(struct udevice *dev)
{
	struct video_uc_plat *plat = dev_get_uclass_plat(dev);

	plat->base = LIUQIN_FB_BASE;
	plat->size = LIUQIN_FB_SIZE;

	return 0;
}

static const struct video_ops liuqin_video_ops = {
};

U_BOOT_DRIVER(liuqin_video) = {
	.name	= "liuqin_video",
	.id	= UCLASS_VIDEO,
	.ops	= &liuqin_video_ops,
	.bind	= liuqin_video_bind,
	.probe	= liuqin_video_probe,
	.flags	= DM_FLAG_PRE_RELOC,
};
