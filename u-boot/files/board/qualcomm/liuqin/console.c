// SPDX-License-Identifier: GPL-2.0+
/*
 * The diagnostic readback channel.
 *
 * This board has no wired UART, so U-Boot's console record and the panel are
 * the only outputs. Both are unusable for the GPT and slot decisions:
 *
 *  - the console record gets polluted by menu redraws and by the vidconsole
 *    writing one character at a time, and reading it consumes it;
 *  - drawing one panel line costs about a second (every glyph is painted into
 *    the ABL framebuffer), so a 640-line dump would take ten minutes and make
 *    "fastboot oem run" time out mid-transaction, which is what wedged the
 *    gadget during the first readback attempts.
 *
 * So every decision goes into a dedicated line ring, which the host reads back
 * verbatim through the fastboot getvar environment fallback
 * (fastboot.<prefix>{,1..N}) and which liuqin_ab_hold() also puts on the panel.
 */

#include <command.h>
#include <console.h>
#include <env.h>
#include <linux/delay.h>
#include <linux/kernel.h>
#include <stdio.h>
#include <vsprintf.h>

#include "liuqin.h"

static char liuqin_outlines[LIUQIN_OUT_LINES][96];
static int liuqin_outn;

/* Set while a path stores its lines without printing them (see the comment in
 * liuqin_out_linef()'s callers): the panel redraws over anything a command
 * returns with, and a slow printf can time a host command out. */
bool liuqin_quiet;

void liuqin_outf(const char *fmt, ...)
{
	char *dst = liuqin_outlines[liuqin_outn % LIUQIN_OUT_LINES];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(dst, sizeof(liuqin_outlines[0]), fmt, ap);
	va_end(ap);
	liuqin_outn++;
	if (!liuqin_quiet)
		printf("%s\n", dst);
}

void liuqin_out_reset(void)
{
	liuqin_outn = 0;
}

/*
 * A getvar response is capped at FASTBOOT_RESPONSE_LEN (64) including the
 * "OKAY" and the variable name, so roughly 56 characters of value survive.
 * Fold longer lines into continuation records marked with two leading spaces
 * (kernel log lines never start with two spaces) and let the host rejoin them.
 */
#define LIUQIN_LINE_CHUNK	56

static void liuqin_out_line(const char *s, size_t l)
{
	size_t off = 0;

	while (off < l) {
		size_t n = l - off;

		if (n > LIUQIN_LINE_CHUNK)
			n = LIUQIN_LINE_CHUNK;
		if (off)
			liuqin_outf("  %.*s", (int)n, s + off);
		else
			liuqin_outf("%.*s", (int)n, s + off);
		off += n;
	}
}

void liuqin_out_linef(const char *fmt, ...)
{
	char buf[160];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	liuqin_out_line(buf, strlen(buf));
}

#define LIUQIN_CON_LINE		110

/* CONFIG_CONSOLE_RECORD keeps the last 64 KiB of console output; that is where
 * every U-Boot message ends up, including the ones the quiet paths deliberately
 * do not print. Reading consumes the record, so this is a one-shot snapshot. */
static void liuqin_dump_console(void)
{
	char line[LIUQIN_CON_LINE];
	int n = 0, len;

	while (!console_record_isempty()) {
		len = console_record_readline(line, sizeof(line));
		if (len < 0) {
			liuqin_outf("con: read error %d after %d lines", len, n);
			return;
		}
		liuqin_out_line(line, len);
		n++;
	}
	liuqin_outf("con: %d lines", n);
}

/*
 * Hand the last console lines to the host through the fastboot getvar
 * environment fallback (fastboot.<prefix>, fastboot.<prefix>1, ...).
 */
void liuqin_console_capture(const char *prefix, int nvars)
{
	char name[24];
	int i, show;

	show = liuqin_outn < LIUQIN_OUT_LINES ? liuqin_outn : LIUQIN_OUT_LINES;
	if (nvars > show)
		nvars = show;
	/* Tell the host how many variables to fetch (newest first). */
	snprintf(name, sizeof(name), "fastboot.%scount", prefix);
	env_set_ulong(name, nvars);
	if (!nvars) {
		/* Always overwrite, so getvar never returns a stale value. */
		snprintf(name, sizeof(name), "fastboot.%s", prefix);
		env_set(name, "(none)");
		return;
	}

	for (i = 0; i < nvars; i++) {
		int idx = (liuqin_outn - 1 - i + 2 * LIUQIN_OUT_LINES) %
			  LIUQIN_OUT_LINES;

		if (i)
			snprintf(name, sizeof(name), "fastboot.%s%d", prefix, i);
		else
			snprintf(name, sizeof(name), "fastboot.%s", prefix);
		env_set(name, liuqin_outlines[idx]);
	}
}

static int do_liuqin_conlog(struct cmd_tbl *cmdtp, int flag, int argc,
			    char *const argv[])
{
	int nvars = argc > 1 ? (int)simple_strtoul(argv[1], NULL, 10) : 200;

	liuqin_out_reset();
	/* Never echo while reading: that would append to the record. */
	liuqin_quiet = true;
	liuqin_dump_console();
	liuqin_quiet = false;
	liuqin_console_capture("con", nvars);

	return 0;
}

U_BOOT_CMD(liuqin_conlog, 2, 0, do_liuqin_conlog,
	"dump the console record into fastboot vars",
	"[nvars] - reads and clears the recorded console output");

int liuqin_ring_lines(void)
{
	return liuqin_outn;
}

/* Print the newest @n lines of the ring on the panel, oldest first. */
void liuqin_ring_print(int n)
{
	int show = liuqin_outn < LIUQIN_OUT_LINES ? liuqin_outn : LIUQIN_OUT_LINES;
	int i;

	if (n > show)
		n = show;
	for (i = n; i > 0; i--) {
		int idx = (liuqin_outn - i + 2 * LIUQIN_OUT_LINES) %
			  LIUQIN_OUT_LINES;

		printf("%s\n", liuqin_outlines[idx]);
	}
	if (!n)
		printf("(the ring is empty)\n");
}

/*
 * Hand the panel back to the menu on a fresh button. The key event that selected
 * the menu entry is dropped first, so the same press cannot satisfy this wait -
 * and getchar() on this board's button keyboard ends in input_getc(), the one
 * busy-wait that runs cyclic callbacks, so the Gunyah vWDT keeps being petted
 * while we wait (drivers/input/input.c).
 */
void liuqin_panel_wait(void)
{
	while (tstc())
		(void)getchar();
	printf("press any button to go back to the menu\n");
	(void)getchar();
}
