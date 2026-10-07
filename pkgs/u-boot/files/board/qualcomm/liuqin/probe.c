// SPDX-License-Identifier: GPL-2.0+
/*
 * The read-only views of the boot chain's state.
 *
 * Both menu entries exist because CONFIG_FASTBOOT_OEM_RUN is off: a host cannot
 * ask this U-Boot to run anything, so the menu is the only way to read the table
 * back - and "Android does not start" is exactly the moment the evidence is
 * needed. Neither of them writes anything, and neither may start doing so
 * (docs/FACTS.md §3.3): a write reachable from here would destroy the evidence
 * it was added for.
 *
 *   liuqin_gptprobe  every LUN's GPT: geometry, both copies compared, and the
 *                    boot_a/boot_b attribute words from each copy.
 *   liuqin_blkscan   the matching lines of one partition - "logfs" being ABL's
 *                    own log, the only account of what the bootloader did to
 *                    the slot table.
 */

#include <blk.h>
#include <command.h>
#include <dm.h>
#include <dm/uclass.h>
#include <linux/kernel.h>
#include <malloc.h>
#include <part.h>
#include <asm/byteorder.h>
#include <stdio.h>
#include <u-boot/crc.h>

#include "liuqin.h"

/*
 * Dump @len bytes as short hex lines, into the ring (so the panel and the host
 * see the same bytes). Eight bytes per line: the getvar channel folds at 56
 * characters, and a folded hex line is still re-assemblable by its continuation
 * marker, while on the panel short lines survive being photographed at an angle.
 */
void liuqin_hexdump(const char *tag, const u8 *p, int len)
{
	char line[80];
	int off, i;

	for (off = 0; off < len; off += 8) {
		int n = snprintf(line, sizeof(line), "%s+%02x:", tag, off);

		for (i = 0; i < 8 && off + i < len; i++)
			n += snprintf(line + n, sizeof(line) - n, " %02x",
				      p[off + i]);
		liuqin_out_linef("%s", line);
	}
}

/* GPT header byte 56 is the disk GUID. It is not the unique GUID printed from a
 * partition entry, and the ABL log calls a mismatch here out as "GUID is not
 * match". This is where the values stay readable - the probe's dump and summary,
 * and the failure landing pad's dump - so a pair that looks CRC-valid cannot
 * hide an identity split. The commit path itself logs only the verdict
 * (gpt.c: "preflight disk-guid SAME/DIFF"). */
static void liuqin_gpt_guid_line(const char *tag, const u8 *guid)
{
	char text[33];
	int i;

	for (i = 0; i < 16; i++)
		snprintf(text + i * 2, sizeof(text) - i * 2, "%02x", guid[i]);
	text[sizeof(text) - 1] = '\0';
	liuqin_out_linef("%s disk-guid %s", tag, text);
}

/*
 * Say everything about the GPT block at @lba: a read error, "not a header" plus
 * the first bytes as they are, or every field the layout is rebuilt from plus
 * both stored CRCs re-checked and the first 16 bytes verbatim. Called where the
 * copy matters - the failure landing pad - because "not usable" on its own
 * cannot be told apart from a read failure, a stale copy, or an alternate_lba
 * that names the wrong block, and this board's panel is the only log.
 */
void liuqin_gpt_dump(struct blk_desc *desc, u64 lba, const char *tag)
{
	u8 *b = memalign(desc->blksz, desc->blksz);
	ulong got;

	if (!b) {
		liuqin_out_linef("%s@%llu: no memory", tag,
				 (unsigned long long)lba);
		return;
	}
	got = blk_dread(desc, lba, 1, b);
	if (got != 1) {
		liuqin_out_linef("%s@%llu: read failed (%lu)", tag,
				 (unsigned long long)lba, got);
		free(b);
		return;
	}
	if (liuqin_le64(b) != GPT_HEADER_SIGNATURE_UBOOT) {
		liuqin_out_linef("%s@%llu: no GPT header, first bytes:", tag,
				 (unsigned long long)lba);
		liuqin_hexdump(tag, b, 16);
		free(b);
		return;
	}

	{
		u32 saved = liuqin_le32(b + 16);
		u32 hdr_calc;
		u64 ent_lba = liuqin_le64(b + 72);
		u32 num = liuqin_le32(b + 80), esz = liuqin_le32(b + 84);
		u64 entry_bytes = (u64)num * esz;
		ulong blks = 0;
		u8 *e;
		bool entry_shape = desc->blksz && num && esz >= GPT_ENTRY_SIZE &&
			entry_bytes <= 1024 * 1024;

		if (entry_shape)
			blks = DIV_ROUND_UP(entry_bytes, desc->blksz);

		liuqin_put_le32(b + 16, 0);
		hdr_calc = crc32(0, b, sizeof(gpt_header));
		liuqin_put_le32(b + 16, saved);

		liuqin_out_linef("%s@%llu: my %llu alt %llu ent %llu n%u e%u %lu blks",
				 tag, (unsigned long long)lba,
				 (unsigned long long)liuqin_le64(b + 24),
				 (unsigned long long)liuqin_le64(b + 32),
				 (unsigned long long)ent_lba, num, esz, blks);
		/* "saved/calculated" - the pair is what tells a torn header from a
		 * valid one, and one line keeps the whole dump on one screen. */
		liuqin_out_linef("%s@%llu use %llu..%llu hdrcrc %08x/%08x %s",
				 tag, (unsigned long long)lba,
				 (unsigned long long)liuqin_le64(b + 40),
				 (unsigned long long)liuqin_le64(b + 48),
				 saved, hdr_calc,
				 hdr_calc == saved ? "ok" : "BAD");
		liuqin_gpt_guid_line(tag, b + 56);
		liuqin_hexdump(tag, b, 16);

		/* Are its entries the same table? Only readable when the header at
		 * least parses; the block is read but never written. */
		if (entry_shape && blks <= 256 &&
		    liuqin_gpt_range_ok(ent_lba, blks, desc->lba)) {
			e = memalign(desc->blksz, blks * desc->blksz);
			if (e && blk_dread(desc, ent_lba, blks, e) == blks) {
				u32 ecrc = liuqin_le32(b + 88);
				u32 ecalc = crc32(0, e, entry_bytes);
				char lbl[24];

				liuqin_out_linef("%s ents@%llu crc %08x/%08x %s",
						 tag, (unsigned long long)ent_lba,
						 ecrc, ecalc,
						 ecrc == ecalc ? "ok" : "stale");
				snprintf(lbl, sizeof(lbl), "%s ents", tag);
				liuqin_hexdump(lbl, e, 16);
			} else {
				liuqin_out_linef("%s ents@%llu: unreadable",
						 tag, (unsigned long long)ent_lba);
			}
			free(e);
		} else if (num && esz >= GPT_ENTRY_SIZE) {
			liuqin_out_linef("%s ents@%llu: outside disk",
					 tag, (unsigned long long)ent_lba);
		}
	}
	free(b);
}

/* Compact facts kept at the end of every probe, especially the panel form. */
static void liuqin_gpt_probe_summary(struct liuqin_gpt *pri,
				     struct liuqin_gpt *bak)
{
	const char *why = NULL;
	gpt_entry *ep, *eb, *xbl, *tail;
	bool pri_hcrc, pri_ecrc;

	pri_hcrc = liuqin_gpt_hdr_crc_ok(pri->hdr);
	pri_ecrc = crc32(0, (const u8 *)pri->ent, pri->num * pri->esz) ==
		le32_to_cpu(pri->hdr->partition_entry_array_crc32);
	liuqin_out_linef("gptp: pri crc H:%s E:%s",
			 pri_hcrc ? "ok" : "BAD",
			 pri_ecrc ? "ok" : "BAD");
	if (!bak) {
		liuqin_out_linef("gptp: bak unavailable");
	} else {
		bool bak_hcrc = liuqin_gpt_hdr_crc_ok(bak->hdr);
		bool bak_ecrc =
			crc32(0, (const u8 *)bak->ent, bak->num * bak->esz) ==
			le32_to_cpu(bak->hdr->partition_entry_array_crc32);

		liuqin_out_linef("gptp: bak crc H:%s E:%s",
				 bak_hcrc ? "ok" : "BAD",
				 bak_ecrc ? "ok" : "BAD");
		if (liuqin_gpt_pair_check(pri, bak, &why))
			liuqin_out_linef("gptp: pair SAME");
		else
			liuqin_out_linef("gptp: pair DIFF %s",
					 why ? why : "unknown");
		liuqin_out_linef("gptp: disk-guid %s",
				 !guidcmp(&pri->hdr->disk_guid,
					  &bak->hdr->disk_guid) ?
				 "SAME" : "DIFF");
		liuqin_gpt_guid_line("gptp pri", pri->hdr->disk_guid.b);
		liuqin_gpt_guid_line("gptp bak", bak->hdr->disk_guid.b);
	}

	ep = liuqin_gpt_find(pri, "boot_a");
	eb = bak ? liuqin_gpt_find(bak, "boot_a") : NULL;
	liuqin_out_linef("gptp: boot_a %04llx/%04llx",
			 (unsigned long long)(ep ? liuqin_ent_attrs(ep) >> 48 : 0),
			 (unsigned long long)(eb ? liuqin_ent_attrs(eb) >> 48 : 0));
	ep = liuqin_gpt_find(pri, "boot_b");
	eb = bak ? liuqin_gpt_find(bak, "boot_b") : NULL;
	liuqin_out_linef("gptp: boot_b %04llx/%04llx",
			 (unsigned long long)(ep ? liuqin_ent_attrs(ep) >> 48 : 0),
			 (unsigned long long)(eb ? liuqin_ent_attrs(eb) >> 48 : 0));

	if (pri->desc && pri->desc->lun == 4 &&
	    pri->desc->lba >= LIUQIN_LAST_PARTI_START &&
	    liuqin_gpt_find(pri, "boot_a")) {
		xbl = liuqin_gpt_find(pri, "xbl_sc_logs");
		tail = liuqin_gpt_find(pri, "last_parti");
		if (xbl)
			liuqin_out_linef("gptp: xbl %llu..%llu",
					 (unsigned long long)le64_to_cpu(xbl->starting_lba),
					 (unsigned long long)le64_to_cpu(xbl->ending_lba));
		else
			liuqin_out_linef("gptp: xbl missing");
		if (tail)
			liuqin_out_linef("gptp: tail %llu..%llu type:%s",
					 (unsigned long long)le64_to_cpu(tail->starting_lba),
					 (unsigned long long)le64_to_cpu(tail->ending_lba),
					 liuqin_ent_unused(tail) ? "empty" : "USED");
		else
			liuqin_out_linef("gptp: tail missing");
	}

	if (liuqin_gpt_semantic_ok(pri, &why))
		liuqin_out_linef("gptp: semantic OK");
	else
		liuqin_out_linef("gptp: semantic BAD %s", why ? why : "unknown");
}

static bool liuqin_gpt_probe_lun(struct blk_desc *d, const char *want,
				 bool panel)
{
	struct liuqin_gpt g, b = {0};
	gpt_entry *e;
	const char *why;
	u64 i, used = 0;
	bool backup_loaded = false;

	/* In panel mode, filter before emitting anything: the old code printed
	 * every LUN's header before discovering that it was not the slot table,
	 * so the final screen was often LUN5 rather than LUN4. */
	if (liuqin_gpt_load(&g, d, GPT_PRIMARY_PARTITION_TABLE_LBA, false)) {
		if (panel && d->lun != 4)
			return false;
		liuqin_outf("gptp: blk dev%d lun%d blksz %lu blocks %llu",
			    d->devnum, d->lun, (ulong)d->blksz,
			    (unsigned long long)d->lba);
		liuqin_outf("gptp: primary GPT cannot be parsed");
		if (panel)
			liuqin_gpt_dump(d, GPT_PRIMARY_PARTITION_TABLE_LBA,
					"gptp pri");
		else
			liuqin_outf("gptp: no valid primary GPT");
		return true;
	}
	if (panel && d->lun != 4 && !liuqin_gpt_find(&g, "boot_a")) {
		liuqin_gpt_free(&g);
		return false;
	}
	liuqin_outf("gptp: blk dev%d lun%d blksz %lu blocks %llu",
		    d->devnum, d->lun, (ulong)d->blksz,
		    (unsigned long long)d->lba);
	liuqin_outf("gptp: hdr alt %llu ent %llu n%llu e%llu",
		    (unsigned long long)le64_to_cpu(g.hdr->alternate_lba),
		    (unsigned long long)g.ent_lba,
		    (unsigned long long)g.num, (unsigned long long)g.esz);
	liuqin_outf("gptp: use %llu..%llu",
		    (unsigned long long)le64_to_cpu(g.hdr->first_usable_lba),
		    (unsigned long long)le64_to_cpu(g.hdr->last_usable_lba));

	/*
	 * Pair check (docs/FACTS.md §4): the two copies have to describe the
	 * same table, which is what a commit interrupted between its two writes
	 * breaks. The boot_a/boot_b attribute words are printed from both
	 * copies, so an attribute that only one of them carries is visible in
	 * the same read.
	 */
	if (liuqin_gpt_load(&b, d, le64_to_cpu(g.hdr->alternate_lba), false)) {
		/* Not a pair to compare, and the reason matters: say what that
		 * block actually holds instead of only "unreadable". */
		liuqin_outf("gptp: xchk bak unreadable");
		if (!panel)
			liuqin_gpt_dump(d, le64_to_cpu(g.hdr->alternate_lba),
					"gptp bak");
	} else {
		backup_loaded = true;
	}
	if (!panel && backup_loaded) {
		if (liuqin_gpt_pair_check(&g, &b, &why))
			liuqin_outf("gptp: xchk pair SAME");
		else
			liuqin_outf("gptp: xchk pair DIFF %s", why);
		for (i = 0; i < 2; i++) {
			char slotname[8];
			gpt_entry *ep, *eb;

			snprintf(slotname, sizeof(slotname), "boot_%c",
				 i ? 'b' : 'a');
			ep = liuqin_gpt_find(&g, slotname);
			if (!ep)
				continue;
			eb = liuqin_gpt_find(&b, slotname);
			liuqin_outf("gptp: xchk %s pri %04llx bak %04llx",
				    slotname,
				    (unsigned long long)(liuqin_ent_attrs(ep) >> 48),
				    (unsigned long long)(eb ?
					liuqin_ent_attrs(eb) >> 48 : 0));
		}
	}
	for (i = 0; i < g.num; i++) {
		char name[PARTNAME_SZ + 1];
		u64 first, last;

		e = liuqin_gpt_ent(&g, i);
		if (liuqin_ent_unused(e))
			continue;
		used++;
		liuqin_ent_name(e, name, sizeof(name));
		if (panel && strcmp(name, "boot_a") && strcmp(name, "boot_b") &&
		    strcmp(name, "xbl_sc_logs"))
			continue;
		first = le64_to_cpu(e->starting_lba);
		last = le64_to_cpu(e->ending_lba);
		liuqin_outf("gptp: #%llu %s %llu %llu %lluK",
			    i + 1, name, (unsigned long long)first,
			    (unsigned long long)last,
			    ((last + 1 - first) * d->blksz) / 1024);
		if (want && !strcmp(name, want)) {
			char tag[24];

			liuqin_outf("gptp: #%llu sz_start blk%lu", i + 1,
				    (ulong)d->blksz);
			liuqin_outf("gptp: #%llu start dec %llu", i + 1,
				    (unsigned long long)first);
			liuqin_outf("gptp: #%llu end dec %llu", i + 1,
				    (unsigned long long)last);
			snprintf(tag, sizeof(tag), "gptp: #%llu type", i + 1);
			liuqin_hexdump(tag, e->partition_type_guid.b, 16);
			snprintf(tag, sizeof(tag), "gptp: #%llu guid", i + 1);
			liuqin_hexdump(tag, e->unique_partition_guid.b, 16);
		}
	}
	liuqin_outf("gptp: %llu used entries", used);
	liuqin_slot_attr_lines(&g);
	/* Always append the decision-making facts last: the panel renderer shows
	 * only the newest lines, while the host still receives the full ring. */
	liuqin_gpt_probe_summary(&g, backup_loaded ? &b : NULL);
	liuqin_gpt_free(&g);
	liuqin_gpt_free(&b);

	return true;
}

static int do_liuqin_gptprobe(struct cmd_tbl *cmdtp, int flag, int argc,
			      char *const argv[])
{
	const char *want = NULL;
	struct udevice *dev;
	bool panel;
	int i, nlun = 0;

	/*
	 * "hold" is the panel mode: probe only the table that carries the slots,
	 * print the result on the panel and wait for a button. It exists because
	 * CONFIG_FASTBOOT_OEM_RUN is off, so a menu entry is the only way to
	 * read this board's table back without a host, and the bootmenu redraws
	 * over anything that does not hold the screen. Read-only either way.
	 */
	panel = liuqin_arg_present(argc, argv, "hold");
	for (i = 1; i < argc; i++)
		if (strcmp(argv[i], "hold"))
			want = argv[i];

	liuqin_out_reset();
	liuqin_quiet = true;

	for (uclass_first_device(UCLASS_BLK, &dev); dev;
	     uclass_next_device(&dev)) {
		struct blk_desc *d = dev_get_uclass_plat(dev);

		if (!d || d->uclass_id != UCLASS_SCSI)
			continue;
		if (liuqin_gpt_probe_lun(d, want, panel))
			nlun++;
	}
	liuqin_outf("gptp: %d luns", nlun);
	liuqin_quiet = false;
	/*
	 * Hand our own lines to the host right here. They must not be left for
	 * liuqin_conlog: that command resets the ring before exporting (its
	 * documented "reads and clears" behaviour), which silently threw away
	 * every probe line the first time this was read back.
	 */
	liuqin_console_capture("gptp", LIUQIN_OUT_LINES);
	env_set_ulong("fastboot.gptprobe", nlun);
	if (nlun == 0)
		printf("gptprobe: no SCSI block devices\n");

	if (panel) {
		printf("--- GPT probe, read-only (fastboot gptp* carries this) ---\n");
		liuqin_ring_print(LIUQIN_RING_SHOW);
		liuqin_panel_wait();
	}

	return 0;
}

U_BOOT_CMD(liuqin_gptprobe, 2, 0, do_liuqin_gptprobe,
	"dump every UFS LUN's GPT into the quiet ring (read-only)",
	"[hold] [name] - export fastboot.gptp{,1..N}; each table's two copies are\n"
	"  compared (xchk lines) and boot_a/boot_b attributes printed from both;\n"
	"  \"name\" additionally prints that partition's type and unique GUID;\n"
	"  \"hold\" probes only the table holding the slots and keeps the result\n"
	"  on the panel until a button - the menu entry's form. Writes nothing.");

/*
 * Read-only scan of one partition for the lines that decide a boot.
 *
 * The only account of what the bootloader did to the slot table is ABL's own
 * log, which lives in the "logfs" partition: which slot it picked and with what
 * retry count, whether it had to rebuild a table copy ("Valid primary and
 * !Valid backup partition table" / "Restore backup partition table by the
 * primary"), whether it rewrote entries ("Error in GPT header, GUID is not
 * match!"), and whether the boot lun it keeps disagrees with the slot it is
 * booting - which fails the boot with EFI_DEVICE_ERROR (ABL 0x49a50, string
 * 0xb6deb) and is invisible in the GPT itself. That log is text in a partition,
 * so it can be read here without a host, without Android, and without a table
 * any slot can boot from - which is the whole point: the evidence has to be
 * readable in exactly the state where Android no longer starts.
 *
 * Only matching lines are emitted, at most LIUQIN_SCAN_KEY_MAX per keyword with
 * the total counted, because a getvar response carries ~56 characters, logfs is
 * 8 MiB, and the interesting lines must survive the flood of a boot that
 * repairs 288 entries. Read-only: no partition is written, no table committed.
 */
#define LIUQIN_SCAN_RUN_MIN	8	/* shorter runs are noise, not log lines */
#define LIUQIN_SCAN_RUN_MAX	100	/* with the offset prefix, one ring line */
#define LIUQIN_SCAN_KEY_MAX	24	/* lines kept per keyword; rest counted */
#define LIUQIN_SCAN_BLOCKS_MAX	(1 << 22) /* extents beyond this are refused */
#define LIUQIN_SCAN_EVERY	64	/* blocks between schedule() calls */

static const char *const liuqin_scan_keys[] = {
	"Boot lun", "BootableSlot", "do not match", "Valid primary",
	"Valid backup", "Restore backup", "Updating GPT", "Updated Partition",
	"Active Slot", "retry count", "unbootable", "New slot", "SetActiveSlot",
	"set_active", "Switching the boot lun", "GUID is not match",
	"Invalid image", "KernelSize", "avb_slot_verify", "Hash of data",
	"LoadImageAndAuth", "Boot Partition is updated",
};

struct liuqin_scan_stat {
	ulong seen;
	ulong shown;
};

static int liuqin_scan_key_index(const char *line)
{
	unsigned int i;

	for (i = 0; i < ARRAY_SIZE(liuqin_scan_keys); i++)
		if (strstr(line, liuqin_scan_keys[i]))
			return (int)i;

	return -1;
}

static int do_liuqin_blkscan(struct cmd_tbl *cmdtp, int flag, int argc,
			     char *const argv[])
{
	struct liuqin_scan_stat stat[ARRAY_SIZE(liuqin_scan_keys)];
	struct liuqin_gpt g = {0};
	struct blk_desc *desc;
	const char *part = NULL;
	gpt_entry *ent;
	u8 *buf = NULL;
	u64 first, last, lba;
	ulong blocks = 0;
	bool quiet, panel;
	unsigned int k;
	int max = LIUQIN_OUT_LINES;
	int i, ret = 0;

	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "hold"))
			continue;
		if (argv[i][0] >= '0' && argv[i][0] <= '9')
			max = (int)simple_strtoul(argv[i], NULL, 10);
		else
			part = argv[i];
	}
	panel = liuqin_arg_present(argc, argv, "hold");
	if (!part)
		return CMD_RET_USAGE;

	memset(stat, 0, sizeof(stat));
	quiet = liuqin_quiet;
	liuqin_quiet = true;
	liuqin_out_reset();

	desc = liuqin_gpt_holding(&g, part);
	if (!desc) {
		liuqin_outf("scan: no GPT holds %s (primary CRC-valid)", part);
		ret = -ENOENT;
		goto out;
	}
	ent = liuqin_gpt_find(&g, part);
	first = le64_to_cpu(ent->starting_lba);
	last = le64_to_cpu(ent->ending_lba);
	if (last < first || last - first >= LIUQIN_SCAN_BLOCKS_MAX) {
		liuqin_outf("scan: %s extent %llu..%llu is not scannable", part,
			    (unsigned long long)first,
			    (unsigned long long)last);
		ret = -EINVAL;
		goto out;
	}
	buf = memalign(desc->blksz, desc->blksz);
	if (!buf) {
		liuqin_outf("scan: no memory for a %lu-byte block",
			    (ulong)desc->blksz);
		ret = -ENOMEM;
		goto out;
	}

	for (lba = first; lba <= last; lba++) {
		char run[LIUQIN_SCAN_RUN_MAX + 1];
		u64 off, run_at = 0;
		int n = 0;

		if (blk_dread(desc, lba, 1, buf) != 1) {
			liuqin_outf("scan: read failed at %llu of %llu",
				    (unsigned long long)lba,
				    (unsigned long long)last);
			break;
		}
		blocks++;
		/* One extra iteration so the run that ends with the block is
		 * flushed by the same code path as every other run. */
		for (off = 0; off <= desc->blksz; off++) {
			u8 c = off < desc->blksz ? buf[off] : 0;
			int key;

			if (c >= 0x20 && c < 0x7f) {
				if (!n)
					run_at = (lba - first) * desc->blksz + off;
				if (n < LIUQIN_SCAN_RUN_MAX)
					run[n++] = c;
				continue;
			}
			if (n >= LIUQIN_SCAN_RUN_MIN) {
				run[n] = '\0';
				key = liuqin_scan_key_index(run);
				if (key >= 0) {
					stat[key].seen++;
					if (stat[key].shown <
					    LIUQIN_SCAN_KEY_MAX) {
						stat[key].shown++;
						liuqin_out_linef("scan +%llu: %s",
								 (unsigned long long)run_at,
								 run);
					}
				}
			}
			n = 0;
		}
		if (!(blocks % LIUQIN_SCAN_EVERY))
			schedule();
	}

	liuqin_outf("scan: %s %llu..%llu, %lu blocks read", part,
		    (unsigned long long)first, (unsigned long long)last, blocks);
	for (k = 0; k < ARRAY_SIZE(liuqin_scan_keys); k++)
		if (stat[k].seen)
			liuqin_outf("scan: \"%s\": %lu seen, %lu shown",
				    liuqin_scan_keys[k], stat[k].seen,
				    stat[k].shown);
out:
	free(buf);
	liuqin_gpt_free(&g);
	liuqin_quiet = quiet;
	liuqin_console_capture("scan", max);
	if (panel) {
		printf("--- %s scan, read-only (fastboot scan* carries this) ---\n",
		       part);
		liuqin_ring_print(LIUQIN_RING_SHOW);
		liuqin_panel_wait();
	}

	return ret;
}

U_BOOT_CMD(liuqin_blkscan, 4, 0, do_liuqin_blkscan,
	"scan a partition for the lines that decide a boot (read-only)",
	"[hold] <part> [max] - emit only the matching lines of <part> into the\n"
	"  quiet ring, exported as fastboot.scan{,1..N}, and count them per\n"
	"  keyword. \"logfs\" carries ABL's own log: slot choice, retry count,\n"
	"  backup restore, entry GUID repairs, boot-lun mismatch. Writes nothing.");
