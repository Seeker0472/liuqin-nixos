/* SPDX-License-Identifier: GPL-2.0+ */
/*
 * Xiaomi Pad 6 Pro (liuqin, SM8475): what the board files share.
 *
 * The board support is split by what a mistake in it can break, because the
 * only log this board has is the panel and only one of these files may write
 * the boot chain's state:
 *
 *   liuqin.c    board init: the Gunyah watchdog, console record, UFS/USB
 *               supplies, and the regulator helpers the others use
 *   video.c     the pre-console panel renderer and the DM video driver
 *   console.c   the console record and the diagnostic ring the host reads back
 *   gpt.c       reading, checking and rewriting one copy of a GPT
 *   qbootctl.c  the A/B identity layer, ported from qbootctl/AOSP
 *   slot.c      what a slot switch means: the state byte, the commands, and
 *               the fastboot hooks the host talks to
 *   probe.c     the read-only views: the GPT probe and the ABL log scan
 *   power.c     restart reasons, the PS_HOLD hand-off, and poweroff
 */

#ifndef __LIUQIN_H
#define __LIUQIN_H

#include <blk.h>
#include <dm/ofnode.h>
#include <linux/types.h>
#include <linux/string.h>
#include <part.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>

#define LIUQIN_PREFIX		"LIUQIN-UBOOT: "

/*
 * One GPT copy: the header block, the entry array, and where they were read
 * from. The types are U-Boot's own (include/part_efi.h), so the fields are
 * named rather than addressed by offset, and liuqin_gpt_load() is the only
 * place that decides whether a copy may be used at all.
 */
struct liuqin_gpt {
	struct blk_desc *desc;
	gpt_header *hdr;	/* one block; the header is sizeof(gpt_header) of it */
	gpt_entry *ent;		/* g->num entries, g->esz bytes apart */
	u64 hdr_lba, ent_lba;
	u64 num, esz;
	ulong blksz, ent_blks;
};

/* Both GPT copies of a table are written, flushed and compared, or the commit
 * fails: a slot switch that half happened is what ABL repairs in the wrong
 * direction (docs/FACTS.md §4). */
enum liuqin_gpt_commit_status {
	LIUQIN_GPT_COMMIT_OK = 0,
	LIUQIN_GPT_COMMIT_WRITE_FAIL,
	LIUQIN_GPT_COMMIT_PAIR_FAIL,
};

u32 liuqin_le32(const void *p);
u64 liuqin_le64(const void *p);
void liuqin_put_le32(void *p, u32 v);
void liuqin_put_le64(void *p, u64 v);

/*
 * LUN4 is the Qualcomm boot-partition table on this unit (docs/FACTS.md §1.1).
 * xbl_sc_logs is a fixed 32-block partition in the canonical table; the
 * zero-type last_parti entry is the expandable tail marker. The tail's actual
 * end is always the primary header's last_usable_lba, so these hold for both
 * storage sizes of the Pad 6 Pro variants.
 */
#define LIUQIN_XBL_SC_LOGS_START	573856ULL
#define LIUQIN_XBL_SC_LOGS_END		573887ULL
#define LIUQIN_LAST_PARTI_START		573888ULL
#define LIUQIN_XBL_SC_LOGS_INDEX	75U	/* GPT entry #76 */
#define LIUQIN_LAST_PARTI_INDEX		76U	/* GPT entry #77 */

bool liuqin_gpt_range_ok(u64 start, u64 blocks, u64 last);
bool liuqin_gpt_hdr_crc_ok(gpt_header *h);
bool liuqin_gpt_crc_ok(const struct liuqin_gpt *g);
int liuqin_gpt_load(struct liuqin_gpt *g, struct blk_desc *desc, u64 hdr_lba,
		    bool validate_crc);
void liuqin_gpt_free(struct liuqin_gpt *g);
gpt_entry *liuqin_gpt_ent(const struct liuqin_gpt *g, u64 i);
u64 liuqin_gpt_index(const struct liuqin_gpt *g, const gpt_entry *e);
gpt_entry *liuqin_gpt_find(const struct liuqin_gpt *g, const char *name);
struct blk_desc *liuqin_gpt_holding(struct liuqin_gpt *g, const char *name);
const char *liuqin_gpt_skip_reason(struct blk_desc *desc);
bool liuqin_gpt_semantic_ok(const struct liuqin_gpt *g, const char **why);
bool liuqin_gpt_pair_check(const struct liuqin_gpt *pri,
			   const struct liuqin_gpt *bak, const char **why);
int liuqin_scsi_sync_cache(struct blk_desc *desc);
enum liuqin_gpt_commit_status liuqin_gpt_commit(struct liuqin_gpt *pri);

/* The 8 attribute bytes of an entry, whole. Read and written as bytes rather
 * than through gpt_entry.attributes.fields: the boot chain's state byte is
 * bits 48-63 of that word and the masks below are written against it. */
u64 liuqin_ent_attrs(const gpt_entry *e);
void liuqin_ent_set_attrs(gpt_entry *e, u64 v);
bool liuqin_ent_unused(const gpt_entry *e);
void liuqin_ent_name(const gpt_entry *e, char *out, size_t len);

/*
 * The A/B identity layer (qbootctl.c), ported from qbootctl's GPT helpers and
 * its UFS boot-LUN handling. A switch to another slot has to move both, or ABL
 * finds a table whose identity does not describe the slot it is booting.
 */
#define LIUQIN_BOOT_LUN_A	1
#define LIUQIN_BOOT_LUN_B	2
/* Size of the active/inactive role buffers the two helpers below fill; the
 * table itself is in qbootctl.c and asserted against this. */
#define LIUQIN_AB_TYPE_GUID_COUNT 21

int liuqin_slot_type_guids_prepare(struct liuqin_gpt *g, char target,
				   char current, u8 active_type[][16],
				   u8 inactive_type[][16]);
int liuqin_slot_type_guids_verify(struct liuqin_gpt *g, char target,
				  const u8 active_type[][16],
				  const u8 inactive_type[][16]);
int liuqin_boot_lun_for_slot(char slot);
int liuqin_boot_lun_prepare(char slot, u32 *before);
int liuqin_boot_lun_commit(char slot, u32 before);

/*
 * The slot state byte (slot.c). It lives in the boot_<slot> GPT attributes:
 * bits 48-49 priority, bit 50 active, bits 51-53 tries_remaining, bit 54
 * successful, bit 55 unbootable (docs/FACTS.md §2).
 */
#define LIUQIN_SLOT_PRIO_MASK	(3ULL << 48)
#define LIUQIN_SLOT_PRIO_2	(2ULL << 48)
#define LIUQIN_SLOT_ACTIVE	(1ULL << 50)
#define LIUQIN_SLOT_TRIES_MASK	(7ULL << 51)
#define LIUQIN_SLOT_SUCCESSFUL	(1ULL << 54)
#define LIUQIN_SLOT_UNBOOTABLE	(1ULL << 55)
#define LIUQIN_SLOT_STATE_MASK	(0xffULL << 48)
/* What a selected slot gets: AOSP fastboot's complete state byte, not a set of
 * bits to merge into what is there. 0x3f is priority 3, active, seven tries,
 * neither successful nor unbootable. */
#define LIUQIN_SLOT_ACTIVE_VALUE	0x3fULL
#define LIUQIN_SLOT_SUCCESSFUL_VALUE	(LIUQIN_SLOT_SUCCESSFUL >> 48)

/* What a caller is doing to the slots. Only a *selection* owns the UFS boot LUN
 * and the type-GUID roles; AOSP's markBootSuccessful writes the successful bit
 * and nothing else (docs/FACTS.md §3.3). */
enum liuqin_slot_action {
	LIUQIN_SLOT_SELECT,	/* make this slot the one the boot chain loads */
	LIUQIN_SLOT_MARK,	/* record that this slot's payload booted */
};

int liuqin_ab_commit_slot(char slot, bool successful,
			  enum liuqin_slot_action action);
void liuqin_ab_hold(const char *op);
/* The two slots' state bytes, one line each (the menu's and the probe's form). */
void liuqin_slot_attr_lines(const struct liuqin_gpt *g);

/*
 * The diagnostic ring (console.c). Every GPT and slot decision goes into it,
 * because the bootmenu redraws the panel the moment a command returns and this
 * board has no wired serial: the host reads the ring back through fastboot
 * getvar (fastboot.<prefix>{,1..N}).
 */
#define LIUQIN_OUT_LINES	640
/* Lines liuqin_ab_hold() puts on the panel: the panel shows ~90 rows of 16x32
 * glyphs and the LUN list, the table facts and the banners take about 30. */
#define LIUQIN_RING_SHOW	56

extern bool liuqin_quiet;

void liuqin_out_reset(void);
void liuqin_outf(const char *fmt, ...);
void liuqin_out_linef(const char *fmt, ...);
void liuqin_console_capture(const char *prefix, int nvars);
void liuqin_ring_print(int n);
int liuqin_ring_lines(void);
void liuqin_panel_wait(void);

/* Read-only views of a table (probe.c). */
void liuqin_hexdump(const char *tag, const u8 *p, int len);
void liuqin_gpt_dump(struct blk_desc *desc, u64 lba, const char *tag);

/* liuqin.c and the two board hooks it shares. */
int liuqin_enable_supply(ofnode node, const char *prop, int uv);
void liuqin_early_video_init(void);

/* power.c: the vendor-style hand-off; 0 when SCM cut PS_HOLD, 1 when the
 * reason pair was valid but SCM returned (the caller may fall back to PSCI). */
int liuqin_normal_reboot(void);

/*
 * Command-line helpers shared by the menu commands: every one of them takes
 * bare words, and the fastboot client sends slot letters with a leading '_'.
 */
static inline bool liuqin_arg_present(int argc, char *const argv[],
				      const char *what)
{
	int i;

	for (i = 1; i < argc; i++)
		if (!strcmp(argv[i], what))
			return true;

	return false;
}

static inline const char *liuqin_arg_slot(const char *arg)
{
	if (*arg == '_')
		arg++;

	return (*arg == 'a' || *arg == 'b') && !arg[1] ? arg : NULL;
}

#endif /* __LIUQIN_H */
