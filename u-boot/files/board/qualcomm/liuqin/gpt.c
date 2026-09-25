// SPDX-License-Identifier: GPL-2.0+
/*
 * Reading, checking and rewriting one copy of a GPT.
 *
 * This is where a slot switch touches media, so the rules here are the ones the
 * boot chain turned out to depend on (docs/FACTS.md §4, §7):
 *
 *  - the copy already on disk is derived data. The backup's position is
 *    computed from the primary, never taken from the copy being replaced: a
 *    table whose backup was left stale is exactly the table a repair has to be
 *    written to, and following the stale copy's own entries_lba would write an
 *    array the platform's readers do not expect there.
 *  - the primary is written first, and both copies are then re-read, CRC
 *    checked and compared. ABL walks the primary first and keeps it as the
 *    per-entry reference it repairs the backup toward, so "primary new, backup
 *    old" is repaired forward while the reverse silently loses the write.
 *  - every write ends in SYNCHRONIZE CACHE. UFS buffers writes: without the
 *    flush the change reads back fine and is gone after the next reset.
 */

#include <asm/byteorder.h>
#include <blk.h>
#include <cyclic.h>
#include <dm.h>
#include <dm/uclass.h>
#include <linux/delay.h>
#include <linux/kernel.h>
#include <malloc.h>
#include <part.h>
#include <scsi.h>
#include <u-boot/crc.h>

#include "liuqin.h"

/* U-Boot's SCSI layer stores READ CAPACITY's answer unchanged, so desc->lba is
 * the last addressable block. */
#define LIUQIN_GPT_LAST_BLOCK(desc)	((u64)(desc)->lba)

/* The primary header is at LBA 1 and its entry array at LBA 2 (the spec's
 * "primary GPT" layout, part_efi.h GPT_PRIMARY_PARTITION_TABLE_LBA). */
#define LIUQIN_GPT_PRI_ENT_LBA		2

/* More entries than this is not a table this board knows how to write, and it
 * bounds both the allocation and the overlap scan below. */
#define LIUQIN_GPT_ENT_BYTES_MAX	(1024 * 1024)

/* The CRC-covered part of the header: the value the spec puts in its
 * header_size field. */
#define LIUQIN_GPT_HDR_BYTES		92

/* The typed view has to be the on-disk layout, or every field named below is a
 * lie: the CRC over sizeof(gpt_header) and the 128-byte entry stride both come
 * from these sizes. */
_Static_assert(sizeof(gpt_header) == LIUQIN_GPT_HDR_BYTES,
	       "gpt_header is not the 92-byte GPT header");
_Static_assert(sizeof(gpt_entry) == GPT_ENTRY_SIZE,
	       "gpt_entry is not the 128-byte GPT entry");


u32 liuqin_le32(const void *p)
{
	const u8 *b = p;

	return b[0] | b[1] << 8 | b[2] << 16 | (u32)b[3] << 24;
}

u64 liuqin_le64(const void *p)
{
	return liuqin_le32(p) | (u64)liuqin_le32((const u8 *)p + 4) << 32;
}

void liuqin_put_le32(void *p, u32 v)
{
	u8 *b = p;

	b[0] = v;
	b[1] = v >> 8;
	b[2] = v >> 16;
	b[3] = v >> 24;
}

void liuqin_put_le64(void *p, u64 v)
{
	liuqin_put_le32(p, (u32)v);
	liuqin_put_le32((u8 *)p + 4, (u32)(v >> 32));
}

u64 liuqin_ent_attrs(const gpt_entry *e)
{
	return liuqin_le64(&e->attributes);
}

void liuqin_ent_set_attrs(gpt_entry *e, u64 v)
{
	liuqin_put_le64(&e->attributes, v);
}

/* The entry's partition name (ASCII in a UTF-16LE field) as a C string. */
void liuqin_ent_name(const gpt_entry *e, char *out, size_t len)
{
	unsigned int i;

	for (i = 0; i + 1 < len && i < PARTNAME_SZ; i++) {
		u16 ch = e->partition_name[i];

		if (!(ch & 0xff) || (ch >> 8))
			break;
		out[i] = ch;
	}
	out[i] = '\0';
}

bool liuqin_ent_unused(const gpt_entry *e)
{
	int i;

	for (i = 0; i < sizeof(e->partition_type_guid); i++)
		if (e->partition_type_guid.b[i])
			return false;

	return true;
}

/* Check [start, start + blocks) without allowing an unsigned wrap. */
bool liuqin_gpt_range_ok(u64 start, u64 blocks, u64 last)
{
	if (!blocks || start > last)
		return false;

	return blocks - 1 <= last - start;
}

/* Is the header CRC of @h the CRC of its own bytes? The community port's writer
 * requires this even of a backup whose entry array it is about to replace
 * (device/boot/liuqin-mark-slot-successful.c), so a header that does not add up
 * is not a layout to write to. */
bool liuqin_gpt_hdr_crc_ok(gpt_header *h)
{
	u32 saved = le32_to_cpu(h->header_crc32);
	bool ok;

	h->header_crc32 = 0;
	ok = crc32(0, (const u8 *)h, sizeof(*h)) == saved;
	h->header_crc32 = cpu_to_le32(saved);

	return ok;
}

/* Do both stored CRCs of @g match what its own bytes produce? A copy that fails
 * this is stale or torn - usable as a source of its own layout, but not a table
 * to trust (see liuqin_gpt_commit()). */
bool liuqin_gpt_crc_ok(const struct liuqin_gpt *g)
{
	if (crc32(0, (const u8 *)g->ent, g->num * g->esz) !=
	    le32_to_cpu(g->hdr->partition_entry_array_crc32))
		return false;

	return liuqin_gpt_hdr_crc_ok(g->hdr);
}

void liuqin_gpt_free(struct liuqin_gpt *g)
{
	free(g->hdr);
	free(g->ent);
	memset(g, 0, sizeof(*g));
}

gpt_entry *liuqin_gpt_ent(const struct liuqin_gpt *g, u64 i)
{
	return (gpt_entry *)((u8 *)g->ent + i * g->esz);
}

u64 liuqin_gpt_index(const struct liuqin_gpt *g, const gpt_entry *e)
{
	return ((const u8 *)e - (const u8 *)g->ent) / g->esz;
}

gpt_entry *liuqin_gpt_find(const struct liuqin_gpt *g, const char *name)
{
	u64 i;

	for (i = 0; i < g->num; i++) {
		gpt_entry *e = liuqin_gpt_ent(g, i);
		unsigned int c;

		for (c = 0; c < PARTNAME_SZ; c++) {
			u16 ch = e->partition_name[c];

			/* Names are ASCII in a UTF-16LE field: the low byte has
			 * to match and the high byte has to be zero. */
			if ((ch & 0xff) != (unsigned char)name[c] || (ch >> 8))
				break;
			if (!name[c])
				return e;
		}
	}

	return NULL;
}

/*
 * Load and sanity check one GPT copy (header + entries) of @desc. @validate_crc
 * additionally requires the copy to pass both CRCs, which also proves that our
 * crc32() convention matches the one the table was written with.
 */
int liuqin_gpt_load(struct liuqin_gpt *g, struct blk_desc *desc, u64 hdr_lba,
		    bool validate_crc)
{
	u64 disk_last, entry_bytes, entry_blks, my_lba, alt_lba, first, last;
	gpt_header *h;
	bool primary;

	memset(g, 0, sizeof(*g));
	if (!desc || !desc->blksz || desc->lba < 2)
		return -EINVAL;
	disk_last = LIUQIN_GPT_LAST_BLOCK(desc);
	if (hdr_lba > disk_last)
		return -EINVAL;
	g->desc = desc;
	g->blksz = desc->blksz;
	g->hdr_lba = hdr_lba;
	g->hdr = memalign(g->blksz, g->blksz);
	if (!g->hdr)
		return -ENOMEM;
	if (blk_dread(desc, hdr_lba, 1, g->hdr) != 1)
		goto bad;
	h = g->hdr;
	if (le64_to_cpu(h->signature) != GPT_HEADER_SIGNATURE_UBOOT)
		goto bad;
	g->num = le32_to_cpu(h->num_partition_entries);
	g->esz = le32_to_cpu(h->sizeof_partition_entry);
	g->ent_lba = le64_to_cpu(h->partition_entry_lba);
	if (le32_to_cpu(h->header_size) != sizeof(*h) || !g->num ||
	    g->esz < GPT_ENTRY_SIZE || g->num * g->esz > LIUQIN_GPT_ENT_BYTES_MAX)
		goto bad;

	my_lba = le64_to_cpu(h->my_lba);
	alt_lba = le64_to_cpu(h->alternate_lba);
	first = le64_to_cpu(h->first_usable_lba);
	last = le64_to_cpu(h->last_usable_lba);
	primary = hdr_lba == GPT_PRIMARY_PARTITION_TABLE_LBA;
	if ((!primary && hdr_lba != disk_last) || my_lba != hdr_lba ||
	    alt_lba != (primary ? disk_last : GPT_PRIMARY_PARTITION_TABLE_LBA) ||
	    first < LIUQIN_GPT_PRI_ENT_LBA || first > last || last >= disk_last)
		goto bad;

	entry_bytes = g->num * g->esz;
	entry_blks = DIV_ROUND_UP(entry_bytes, g->blksz);
	if (!liuqin_gpt_range_ok(g->ent_lba, entry_blks, disk_last))
		goto bad;
	if (primary) {
		if (g->ent_lba != LIUQIN_GPT_PRI_ENT_LBA || g->ent_lba > first ||
		    entry_blks > first - g->ent_lba)
			goto bad;
	} else {
		if (last == (u64)-1 || g->ent_lba != last + 1 ||
		    entry_blks > hdr_lba - g->ent_lba)
			goto bad;
	}
	g->ent_blks = (ulong)entry_blks;
	if (validate_crc && !liuqin_gpt_hdr_crc_ok(h))
		goto bad;
	g->ent = memalign(g->blksz, g->ent_blks * g->blksz);
	if (!g->ent)
		goto bad;
	if (blk_dread(desc, g->ent_lba, g->ent_blks, g->ent) != g->ent_blks)
		goto bad;
	if (validate_crc && !liuqin_gpt_crc_ok(g))
		goto bad;

	return 0;
bad:
	liuqin_gpt_free(g);
	return -EINVAL;
}

/*
 * Classify a primary GPT that liuqin_gpt_load() rejected. The loader is
 * intentionally a boolean gate for its many callers, but collapsing a dead UFS
 * link, a missing header, a bad header CRC and a missing partition into one "no
 * GPT" line made the only recovery console nearly useless. This second,
 * read-only pass is only used by liuqin_gpt_holding() for a compact per-LUN
 * diagnostic; it never changes the acceptance rules above.
 */
const char *liuqin_gpt_skip_reason(struct blk_desc *desc)
{
	u8 *hdr = NULL, *ent = NULL;
	u64 disk_last, ent_lba, first, last, entry_bytes, entry_blks;
	u32 num, esz, saved, calc;
	const char *reason;

	if (!desc || !desc->blksz || desc->lba < 2)
		return "invalid block device";
	hdr = memalign(desc->blksz, desc->blksz);
	if (!hdr)
		return "no memory for GPT header";
	if (blk_dread(desc, GPT_PRIMARY_PARTITION_TABLE_LBA, 1, hdr) != 1) {
		reason = "GPT header unreadable";
		goto out;
	}
	if (liuqin_le64(hdr) != GPT_HEADER_SIGNATURE_UBOOT) {
		reason = "no GPT header";
		goto out;
	}

	num = liuqin_le32(hdr + 80);
	esz = liuqin_le32(hdr + 84);
	entry_bytes = (u64)num * esz;
	if (liuqin_le32(hdr + 12) != sizeof(gpt_header) || !num ||
	    esz < GPT_ENTRY_SIZE || entry_bytes > LIUQIN_GPT_ENT_BYTES_MAX) {
		reason = "GPT header fields";
		goto out;
	}

	disk_last = LIUQIN_GPT_LAST_BLOCK(desc);
	ent_lba = liuqin_le64(hdr + 72);
	first = liuqin_le64(hdr + 40);
	last = liuqin_le64(hdr + 48);
	if (liuqin_le64(hdr + 24) != GPT_PRIMARY_PARTITION_TABLE_LBA ||
	    liuqin_le64(hdr + 32) != disk_last ||
	    first < LIUQIN_GPT_PRI_ENT_LBA || first > last || last >= disk_last) {
		reason = "GPT header geometry/alternate";
		goto out;
	}

	entry_blks = DIV_ROUND_UP(entry_bytes, desc->blksz);
	if (!liuqin_gpt_range_ok(ent_lba, entry_blks, disk_last) ||
	    ent_lba != LIUQIN_GPT_PRI_ENT_LBA || ent_lba > first ||
	    entry_blks > first - ent_lba) {
		reason = "GPT entry geometry";
		goto out;
	}

	saved = liuqin_le32(hdr + 16);
	liuqin_put_le32(hdr + 16, 0);
	calc = crc32(0, hdr, sizeof(gpt_header));
	liuqin_put_le32(hdr + 16, saved);
	if (calc != saved) {
		reason = "GPT header CRC";
		goto out;
	}

	ent = memalign(desc->blksz, entry_blks * desc->blksz);
	if (!ent) {
		reason = "no memory for GPT entries";
		goto out;
	}
	if (blk_dread(desc, ent_lba, entry_blks, ent) != entry_blks) {
		reason = "GPT entries unreadable";
		goto out;
	}
	if (crc32(0, ent, entry_bytes) != liuqin_le32(hdr + 88)) {
		reason = "GPT entries CRC";
		goto out;
	}
	reason = "GPT validation failed";
out:
	free(ent);
	free(hdr);

	return reason;
}

/*
 * Find the GPT that holds @name and load its primary copy into @g. boot_a and
 * boot_b live on their own LUN (4 on this device), so the table has to be
 * located by what it contains, not by a device number.
 *
 * Return: the block device on success (@g populated), NULL otherwise (@g
 * released).
 */
struct blk_desc *liuqin_gpt_holding(struct liuqin_gpt *g, const char *name)
{
	struct udevice *dev;
	bool quiet = liuqin_quiet;
	int nscsi = 0;

	/* Finding a slot is also used by fastboot getvar hooks. Keep the per-LUN
	 * explanations in the diagnostic ring without painting one slow line per
	 * LUN to the panel or delaying a host response. */
	liuqin_quiet = true;

	for (uclass_first_device(UCLASS_BLK, &dev); dev;
	     uclass_next_device(&dev)) {
		struct blk_desc *desc = dev_get_uclass_plat(dev);

		if (!desc || desc->uclass_id != UCLASS_SCSI)
			continue;
		nscsi++;
		if (liuqin_gpt_load(g, desc, GPT_PRIMARY_PARTITION_TABLE_LBA,
				    true)) {
			liuqin_out_linef("gpt: skip lun%d for %s: %s", desc->lun,
					 name, liuqin_gpt_skip_reason(desc));
			continue;
		}
		if (liuqin_gpt_find(g, name)) {
			liuqin_quiet = quiet;
			return desc;
		}
		liuqin_out_linef("gpt: skip lun%d for %s: GPT valid, entry absent",
				 desc->lun, name);
		liuqin_gpt_free(g);
	}
	if (!nscsi)
		liuqin_out_linef("gpt: no SCSI LUNs for %s (UFS not enumerated)",
				 name);
	liuqin_quiet = quiet;

	return NULL;
}

/*
 * Check the semantic invariants that CRCs cannot express. In particular, the
 * GPT entry array in the incident was internally CRC-valid while entry 76 had
 * been enlarged from xbl_sc_logs into the last_parti tail. Qualcomm's tools
 * expose three raw shapes for this area: the canonical table has a zero-type
 * last_parti marker at #77; some ABL/fixgpt paths omit that marker and let
 * xbl_sc_logs run to last_usable; and the device can retain the zero-type
 * marker while xbl_sc_logs has nevertheless grown to last_usable. The last form
 * is not an allocated overlap (the marker has no type GUID), and its empty
 * entry may retain either the old placeholder end or last_usable; both forms
 * are present in real tables seen after ABL repair. All three are recognized
 * raw shapes; an xbl end somewhere between the canonical end and last_usable is
 * still rejected as an unknown partial geometry.
 *
 * Tables without boot_a (the other UFS LUNs) still get the generic range and
 * overlap checks. The fixed Qualcomm layout check is limited to the LUN that
 * contains the A/B boot entries, so the host harness and other LUN geometries
 * are not coupled to this platform-specific rule.
 */
bool liuqin_gpt_semantic_ok(const struct liuqin_gpt *g, const char **why)
{
	u64 i, j, first_usable, last_usable;
	gpt_entry *xbl, *tail;

	*why = NULL;
	if (!g || !g->hdr || !g->ent || !g->num || !g->esz) {
		*why = "empty";
		return false;
	}

	first_usable = le64_to_cpu(g->hdr->first_usable_lba);
	last_usable = le64_to_cpu(g->hdr->last_usable_lba);
	for (i = 0; i < g->num; i++) {
		gpt_entry *e = liuqin_gpt_ent(g, i);
		u64 first, last;

		if (liuqin_ent_unused(e))
			continue;
		first = le64_to_cpu(e->starting_lba);
		last = le64_to_cpu(e->ending_lba);
		if (first < first_usable || first > last || last > last_usable) {
			*why = "entry-range";
			return false;
		}
		for (j = 0; j < i; j++) {
			gpt_entry *o = liuqin_gpt_ent(g, j);
			u64 other_first, other_last;

			if (liuqin_ent_unused(o))
				continue;
			other_first = le64_to_cpu(o->starting_lba);
			other_last = le64_to_cpu(o->ending_lba);
			if (first <= other_last && other_first <= last) {
				*why = "entry-overlap";
				return false;
			}
		}
	}

	if (!g->desc || g->desc->lun != 4 ||
	    g->desc->lba < LIUQIN_LAST_PARTI_START ||
	    !liuqin_gpt_find(g, "boot_a"))
		return true;

	xbl = liuqin_gpt_find(g, "xbl_sc_logs");
	tail = liuqin_gpt_find(g, "last_parti");
	if (!xbl) {
		*why = "fixed-entry-missing";
		return false;
	}
	if (liuqin_gpt_index(g, xbl) != LIUQIN_XBL_SC_LOGS_INDEX) {
		*why = "fixed-entry-position";
		return false;
	}
	if (le64_to_cpu(xbl->starting_lba) != LIUQIN_XBL_SC_LOGS_START ||
	    (tail && le64_to_cpu(xbl->ending_lba) != LIUQIN_XBL_SC_LOGS_END &&
	     le64_to_cpu(xbl->ending_lba) != last_usable) ||
	    (!tail && (le64_to_cpu(xbl->ending_lba) < LIUQIN_XBL_SC_LOGS_END ||
		       le64_to_cpu(xbl->ending_lba) > last_usable))) {
		*why = "xbl-sc-logs-geometry";
		return false;
	}
	if (tail) {
		if (liuqin_gpt_index(g, tail) != LIUQIN_LAST_PARTI_INDEX) {
			*why = "fixed-entry-position";
			return false;
		}
		if (!liuqin_ent_unused(tail) ||
		    le64_to_cpu(tail->starting_lba) != LIUQIN_LAST_PARTI_START ||
		    (le64_to_cpu(tail->ending_lba) != LIUQIN_XBL_SC_LOGS_END &&
		     le64_to_cpu(tail->ending_lba) != last_usable)) {
			*why = "last-parti-geometry";
			return false;
		}
	}

	return true;
}

/*
 * UFS devices buffer writes: after rewriting the GPT a read-back still succeeds
 * from the device's volatile cache, so the change can silently be lost on the
 * next reset. Flush it with the same 10-byte SCSI command used by Xiaomi's
 * sd.c. The block device owns the SCSI child, so use its parent controller
 * instead of whichever controller happens to be first in the uclass; the
 * command's LUN is the LUN whose GPT we just changed.
 */
int liuqin_scsi_sync_cache(struct blk_desc *desc)
{
	struct udevice *sdev;
	struct scsi_cmd cmd;
	int attempt, ret = -ENODEV;

	if (!desc || !desc->bdev)
		return -ENODEV;
	sdev = dev_get_parent(desc->bdev);
	if (!sdev || device_get_uclass_id(sdev) != UCLASS_SCSI)
		return -ENODEV;

	for (attempt = 1; attempt <= 3; attempt++) {
		memset(&cmd, 0, sizeof(cmd));
		cmd.target = desc->target;
		cmd.lun = desc->lun;
		cmd.cmd[0] = SCSI_SYNC_CACHE;
		cmd.cmdlen = 10;
		cmd.dma_dir = DMA_NONE;

		ret = scsi_exec(sdev, &cmd);
		if (!ret)
			break;
		schedule();
	}
	liuqin_out_linef("sync-cache dev%d target%d lun%d attempts%d ret=%d",
			 desc->devnum, desc->target, desc->lun, attempt, ret);

	return ret;
}

/*
 * Write one copy, flush it, and read it back. blk_dwrite() only reports that
 * the transfer completed, not that it landed as intended, so a copy that does
 * not round-trip is an error here rather than a success nobody notices.
 */
static int liuqin_gpt_write(struct liuqin_gpt *g)
{
	u8 *hdr_rb, *ent_rb;
	int ret;

	/* Allocate both verification buffers before the first write: an OOM must
	 * fail closed rather than leave a one-sided commit on disk. */
	hdr_rb = memalign(g->blksz, g->blksz);
	ent_rb = memalign(g->blksz, g->ent_blks * g->blksz);
	if (!hdr_rb || !ent_rb) {
		free(hdr_rb);
		free(ent_rb);
		return -ENOMEM;
	}

	if (blk_dwrite(g->desc, g->ent_lba, g->ent_blks, g->ent) != g->ent_blks) {
		ret = -EIO;
		goto out;
	}
	if (blk_dwrite(g->desc, g->hdr_lba, 1, g->hdr) != 1) {
		ret = -EIO;
		goto out;
	}
	ret = liuqin_scsi_sync_cache(g->desc);
	if (ret)
		goto out;

	if (blk_dread(g->desc, g->ent_lba, g->ent_blks, ent_rb) != g->ent_blks ||
	    memcmp(ent_rb, g->ent, g->ent_blks * g->blksz)) {
		ret = -EIO;
		goto out;
	}
	if (blk_dread(g->desc, g->hdr_lba, 1, hdr_rb) != 1 ||
	    memcmp(hdr_rb, g->hdr, g->blksz)) {
		ret = -EIO;
		goto out;
	}
	ret = 0;
out:
	free(hdr_rb);
	free(ent_rb);

	return ret;
}

/*
 * Are the two GPT copies of one table the same table?
 *
 * A copy is self-consistent when its own CRCs check out, and that says nothing
 * about the pair: the entry arrays have to be byte-identical and each header
 * has to point at the other. Both copies of the archived stock tables are
 * byte-identical, so this is the healthy state, and an interrupted commit -
 * backup written, primary not - is what it catches (docs/FACTS.md §4).
 *
 * The facts each copy guarantees on its own (my_lba matches where it was read,
 * header size, the primary's entries_lba) are checked by liuqin_gpt_load();
 * what is checked here is only what relates the two.
 */
bool liuqin_gpt_pair_check(const struct liuqin_gpt *pri,
			   const struct liuqin_gpt *bak, const char **why)
{
	*why = NULL;

	if (!liuqin_gpt_crc_ok(pri) || !liuqin_gpt_crc_ok(bak))
		*why = "crc";
	else if (pri->num != bak->num || pri->esz != bak->esz ||
		 pri->blksz != bak->blksz)
		*why = "geometry";
	else if (memcmp(pri->ent, bak->ent, pri->num * pri->esz))
		*why = "entries";
	else if (le32_to_cpu(pri->hdr->revision) !=
			 le32_to_cpu(bak->hdr->revision) ||
		 guidcmp(&pri->hdr->disk_guid, &bak->hdr->disk_guid))
		*why = "identity";
	else if (le64_to_cpu(pri->hdr->alternate_lba) != bak->hdr_lba ||
		 le64_to_cpu(bak->hdr->alternate_lba) != pri->hdr_lba ||
		 bak->ent_lba != le64_to_cpu(pri->hdr->last_usable_lba) + 1 ||
		 bak->ent_lba == pri->ent_lba)
		*why = "headers";
	else if (le64_to_cpu(pri->hdr->first_usable_lba) !=
			 le64_to_cpu(bak->hdr->first_usable_lba) ||
		 le64_to_cpu(pri->hdr->last_usable_lba) !=
			 le64_to_cpu(bak->hdr->last_usable_lba) ||
		 le32_to_cpu(pri->hdr->partition_entry_array_crc32) !=
			 le32_to_cpu(bak->hdr->partition_entry_array_crc32) ||
		 !liuqin_gpt_range_ok(pri->ent_lba, pri->ent_blks,
				      le64_to_cpu(pri->hdr->first_usable_lba) - 1) ||
		 !liuqin_gpt_range_ok(bak->ent_lba, bak->ent_blks,
				      bak->hdr_lba - 1))
		*why = "fields";
	else
		return true;

	return false;
}

/*
 * Where the backup copy of @pri goes - derived from the primary, because that
 * is where the layout lives.
 *
 * The primary header names the backup's own block (alternate_lba) and reserves
 * an entry area at each end of the table: its own array starts at LBA 2, the
 * backup's sits directly below its header. On this unit both areas hold 16 KiB
 * (first_usable_lba = 6, last_usable_lba = disk_last - 5), and every one of the
 * six LUNs the factory wrote keeps the backup array at "last_usable_lba + 1",
 * which is also the position the community port's writer pins down ("disk_lbas
 * - 5", device/boot/liuqin-mark-slot-successful.c). The primary's own array has
 * to sit in its half the same way, so both positions are checked against those
 * reserved areas before anything is written.
 *
 * The copy already on disk is only described, never followed: it is derived
 * data (see the file comment). @bak->hdr_ok says its header block is a GPT
 * header for that LBA with a valid CRC (its entry array is not re-read here -
 * the commit rewrites both copies from the primary, and a stale array is what
 * the failure landing pad's dump of that copy reports), and @bak->guid_differs
 * says its disk GUID is not the primary's.
 *
 * Return: false when the primary's own fields do not describe two headers with
 * a reserved entry area each (then nothing may be written at all).
 */
struct liuqin_gpt_bak {
	u64 hdr_lba;		/* where the backup header goes */
	u64 ent_lba;		/* where its entry array goes */
	u64 resv_blks;		/* blocks the platform reserves for that array */
	bool hdr_ok;		/* the copy on disk is a GPT header with a good CRC */
	bool guid_differs;	/* ...whose disk GUID is not the primary's */
};

static bool liuqin_gpt_bak_layout(const struct liuqin_gpt *pri,
				  struct liuqin_gpt_bak *bak)
{
	gpt_header *h = pri->hdr;
	u64 alt_lba = le64_to_cpu(h->alternate_lba);
	u64 first = le64_to_cpu(h->first_usable_lba);
	u64 last = le64_to_cpu(h->last_usable_lba);
	u64 disk_last = pri->desc ? LIUQIN_GPT_LAST_BLOCK(pri->desc) : 0;
	u64 reserve;
	u8 *b;

	memset(bak, 0, sizeof(*bak));
	bak->hdr_lba = alt_lba;
	if (!pri->desc || pri->hdr_lba != GPT_PRIMARY_PARTITION_TABLE_LBA ||
	    disk_last < 2 || le64_to_cpu(h->my_lba) != pri->hdr_lba ||
	    alt_lba != disk_last || first < LIUQIN_GPT_PRI_ENT_LBA ||
	    first > last || last >= alt_lba ||
	    pri->ent_lba != LIUQIN_GPT_PRI_ENT_LBA ||
	    pri->ent_blks > first - pri->ent_lba) {
		liuqin_out_linef("pri: names backup %llu, last block %llu: no layout",
				 (unsigned long long)alt_lba,
				 (unsigned long long)disk_last);
		return false;
	}
	/* last < alt_lba was established above, so last + 1 is safe. */
	bak->ent_lba = last + 1;
	reserve = alt_lba - bak->ent_lba;
	if (!reserve || reserve < pri->ent_blks ||
	    !liuqin_gpt_range_ok(bak->ent_lba, pri->ent_blks, alt_lba - 1)) {
		liuqin_out_linef("pri: backup reserve at %llu before %llu is unusable",
				 (unsigned long long)bak->ent_lba,
				 (unsigned long long)alt_lba);
		return false;
	}
	bak->resv_blks = reserve;

	liuqin_out_linef("pri: hdr %llu ent %llu blks %lu resv %llu alt %llu use %llu..%llu",
			 (unsigned long long)pri->hdr_lba,
			 (unsigned long long)pri->ent_lba, pri->ent_blks,
			 (unsigned long long)(first - pri->ent_lba),
			 (unsigned long long)alt_lba, (unsigned long long)first,
			 (unsigned long long)last);

	b = memalign(pri->blksz, pri->blksz);
	if (b) {
		if (blk_dread(pri->desc, alt_lba, 1, b) == 1) {
			gpt_header *bh = (gpt_header *)b;

			if (le64_to_cpu(bh->signature) ==
					GPT_HEADER_SIGNATURE_UBOOT &&
			    le32_to_cpu(bh->header_size) == sizeof(*bh) &&
			    le64_to_cpu(bh->my_lba) == alt_lba &&
			    liuqin_gpt_hdr_crc_ok(bh)) {
				bak->hdr_ok = true;
				bak->guid_differs =
					!guidcmp(&bh->disk_guid, &h->disk_guid);
			}
		}
		free(b);
	}
	liuqin_out_linef("bak: hdr %llu ent %llu resv %llu (disk copy %s)",
			 (unsigned long long)bak->hdr_lba,
			 (unsigned long long)bak->ent_lba,
			 (unsigned long long)bak->resv_blks,
			 bak->hdr_ok ? "valid" : "unusable");

	return true;
}

/*
 * Build a copy of the table from @pri's own bytes, placed at @hdr_lba, pointing
 * back at @alt_lba, with its entry array at @ent_lba. This matches the
 * community liuqin-mark-slot-successful writer; bytes beyond the CRC-covered
 * array are GPT padding and are not part of a slot switch.
 */
static int liuqin_gpt_prepare(struct liuqin_gpt *g, const struct liuqin_gpt *pri,
			      u64 hdr_lba, u64 alt_lba, u64 ent_lba)
{
	g->desc = pri->desc;
	g->blksz = pri->blksz;
	g->hdr_lba = hdr_lba;
	g->ent_lba = ent_lba;
	g->num = pri->num;
	g->esz = pri->esz;
	g->ent_blks = DIV_ROUND_UP(g->num * g->esz, g->blksz);
	g->hdr = memalign(g->blksz, g->blksz);
	g->ent = memalign(g->blksz, g->ent_blks * g->blksz);
	if (!g->hdr || !g->ent) {
		liuqin_gpt_free(g);
		return -ENOMEM;
	}
	memset(g->ent, 0, g->ent_blks * g->blksz);
	memcpy(g->ent, pri->ent, g->num * g->esz);
	memcpy(g->hdr, pri->hdr, pri->blksz);
	g->hdr->my_lba = cpu_to_le64(hdr_lba);
	g->hdr->alternate_lba = cpu_to_le64(alt_lba);
	g->hdr->partition_entry_lba = cpu_to_le64(ent_lba);
	liuqin_put_le32(&g->hdr->partition_entry_array_crc32,
			crc32(0, (const u8 *)g->ent, g->num * g->esz));
	liuqin_put_le32(&g->hdr->header_crc32, 0);
	liuqin_put_le32(&g->hdr->header_crc32,
			crc32(0, (const u8 *)g->hdr, sizeof(*g->hdr)));

	return 0;
}

/*
 * Flush the modified primary table first, then the backup copy.
 *
 * The order matters because of how ABL reads a table: its parser walks the
 * primary first (LBA 1, then AlternateLBA) and keeps a per-entry reference of
 * what it read in a runtime table (0xc3374 in the A15 abl_a dump, 0x84 stride).
 * When that reference disagrees with an entry - either in the entry's type GUID
 * (logged as "Error in GPT header, GUID is not match!", 0x44a18) or in the
 * entry's eight attribute bytes (copied back in silently, 0x44848-0x44970) -
 * ABL repairs the entry it is looking at *toward* that reference. The primary
 * is therefore the copy whose bytes decide, and a tear has to leave the primary
 * holding the new state: "primary new, backup old" is repaired forward by ABL,
 * while "backup new, primary old" is repaired backwards and silently loses the
 * switch. ABL's own writer writes the primary's pieces before the backup's for
 * the same reason.
 */
enum liuqin_gpt_commit_status liuqin_gpt_commit(struct liuqin_gpt *pri)
{
	enum liuqin_gpt_commit_status st = LIUQIN_GPT_COMMIT_WRITE_FAIL;
	struct liuqin_gpt bak = {0}, pri_w = {0}, pri_v = {0}, bak_v = {0};
	struct liuqin_gpt_bak plan;
	const char *why = NULL;

	if (!liuqin_gpt_semantic_ok(pri, &why)) {
		liuqin_out_linef("commit: semantic GPT check failed (%s)",
				 why ? why : "unknown");
		goto out;
	}
	if (!liuqin_gpt_bak_layout(pri, &plan)) {
		liuqin_out_linef("commit: primary describes no backup layout");
		goto out;
	}
	if (!plan.hdr_ok)
		liuqin_out_linef("commit: backup preflight unreadable; rebuilding pair");
	else if (plan.guid_differs)
		liuqin_out_linef("commit: preflight disk-guid DIFF; rebuilding pair");
	else
		liuqin_out_linef("commit: preflight disk-guid SAME");

	if (liuqin_gpt_prepare(&bak, pri, plan.hdr_lba, pri->hdr_lba,
			       plan.ent_lba) ||
	    liuqin_gpt_prepare(&pri_w, pri, pri->hdr_lba, plan.hdr_lba,
			       pri->ent_lba)) {
		liuqin_out_linef("commit: no memory for the copies");
		goto out;
	}

	/*
	 * Primary first: it is the copy ABL takes as its per-entry reference and
	 * repairs the other copy toward, so an interrupted commit has to leave
	 * the new state on the primary (see the comment above).
	 */
	if (liuqin_gpt_write(&pri_w)) {
		liuqin_out_linef("commit: primary write failed, backup still the old table - rerun");
		goto out;
	}
	if (liuqin_gpt_write(&bak)) {
		liuqin_out_linef("commit: backup write failed, primary already new - ABL will repair the backup forward");
		goto out;
	}
	if (liuqin_gpt_load(&pri_v, pri->desc, GPT_PRIMARY_PARTITION_TABLE_LBA,
			    true) ||
	    liuqin_gpt_load(&bak_v, pri->desc, plan.hdr_lba, true)) {
		liuqin_out_linef("commit: rewrite does not read back cleanly");
		st = LIUQIN_GPT_COMMIT_PAIR_FAIL;
		goto out;
	}
	if (!liuqin_gpt_pair_check(&pri_v, &bak_v, &why)) {
		liuqin_out_linef("commit: copies disagree (%s)", why ? why : "?");
		st = LIUQIN_GPT_COMMIT_PAIR_FAIL;
		goto out;
	}

	liuqin_out_linef("commit: both copies written, flushed and equal");
	st = LIUQIN_GPT_COMMIT_OK;
out:
	liuqin_gpt_free(&bak);
	liuqin_gpt_free(&pri_w);
	liuqin_gpt_free(&pri_v);
	liuqin_gpt_free(&bak_v);

	return st;
}
