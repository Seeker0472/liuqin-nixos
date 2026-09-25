// SPDX-License-Identifier: GPL-2.0+
/*
 * partlog - append boot log records to a raw GPT partition (or a RAM
 * ring buffer) so they survive a crash and can be read back on the next
 * boot (e.g. from an Android root shell via dd on the minidump partition).
 *
 * Record format (little-endian), each record starts on a block boundary:
 *
 *   offset  size  field
 *   0x00    12    magic "LIUQINLOG1" (NUL padded)
 *   0x0c    4     seq      monotonically increasing record number
 *   0x10    4     len      payload length in bytes
 *   0x14    4     crc32    CRC32 of the payload
 *   0x18    4     hdr_crc  CRC32 of bytes 0x00..0x17
 *   0x1c    ...   reserved, zero
 *   0x200   len   payload, followed by zero padding to block size
 *
 * Appending scans from the start of the area for the first block without
 * a valid header and writes the new record there.
 */

#include <command.h>
#include <env.h>
#include <blk.h>
#include <part.h>
#include <malloc.h>
#include <vsprintf.h>
#include <asm/global_data.h>
#include <membuff.h>
#include <u-boot/crc.h>
#include <linux/ctype.h>

DECLARE_GLOBAL_DATA_PTR;

#define PARTLOG_MAGIC		"LIUQINLOG1"
#define PARTLOG_MAGIC_LEN	12
#define PARTLOG_HDR_BLKS	1
#define PARTLOG_MAX_PAYLOAD	(256 * 1024)

#define PARTLOG_RAM_DEFAULT_ADDR	0xa7000000UL
#define PARTLOG_RAM_DEFAULT_SIZE	0x400000UL

struct partlog_hdr {
	char	magic[PARTLOG_MAGIC_LEN];
	u32	seq;
	u32	len;
	u32	crc32;
	u32	hdr_crc;
} __packed;

struct partlog_area {
	bool		ram;
	/* block backend */
	struct blk_desc	*desc;
	struct disk_partition info;
	/* ram backend */
	ulong		ram_base;
	ulong		ram_size;
	/* common */
	uint		blksz;
	ulong		blocks;		/* total writable blocks */
	ulong		next;		/* next free block (set by scan) */
	u32		next_seq;
};

static void partlog_warn(const struct partlog_area *a)
{
	if (a->ram)
		printf("partlog: writing RAM log area 0x%lx-0x%lx\n",
		       a->ram_base, a->ram_base + a->ram_size - 1);
	else
		printf("partlog: WARNING: raw writes to scsi %d, partition "
		       "'%s' (start 0x%lx); existing content will be "
		       "destroyed\n", a->desc->devnum, a->info.name,
		       (ulong)a->info.start);
}

static bool partlog_hdr_valid(const struct partlog_hdr *h)
{
	struct partlog_hdr tmp;

	if (memcmp(h->magic, PARTLOG_MAGIC, PARTLOG_MAGIC_LEN))
		return false;
	if (h->len > PARTLOG_MAX_PAYLOAD)
		return false;
	memcpy(&tmp, h, sizeof(tmp));
	tmp.hdr_crc = 0;
	return crc32(0, (const uchar *)&tmp, sizeof(tmp)) == h->hdr_crc;
}

static int partlog_read_blk(struct partlog_area *a, ulong blk, void *buf,
			    ulong count)
{
	if (a->ram) {
		if (blk + count > a->blocks)
			return -1;
		memcpy(buf, (void *)(a->ram_base + blk * a->blksz),
		       count * a->blksz);
		return 0;
	}
	if (blk + count > a->blocks)
		return -1;
	return blk_dread(a->desc, a->info.start + blk, count, buf) == count ?
		0 : -1;
}

static int partlog_write_blk(struct partlog_area *a, ulong blk,
			     const void *buf, ulong count)
{
	if (a->ram) {
		if (blk + count > a->blocks)
			return -1;
		memcpy((void *)(a->ram_base + blk * a->blksz), buf,
		       count * a->blksz);
		return 0;
	}
	if (blk + count > a->blocks)
		return -1;
	return blk_dwrite(a->desc, a->info.start + blk, count,
			  (void *)buf) == count ? 0 : -1;
}

/* Find the first block after the last valid record. */
static int partlog_scan(struct partlog_area *a)
{
	struct partlog_hdr *h;
	ulong blk = 0;
	u32 seq = 0;

	h = malloc(a->blksz);
	if (!h)
		return -ENOMEM;
	while (blk < a->blocks) {
		if (partlog_read_blk(a, blk, h, 1))
			break;
		if (!partlog_hdr_valid(h))
			break;
		seq = h->seq;
		blk += PARTLOG_HDR_BLKS + DIV_ROUND_UP(h->len, a->blksz);
	}
	free(h);
	a->next = blk;
	a->next_seq = seq + 1;
	if (a->ram && blk >= a->blocks) {
		/* RAM area full: wrap around, oldest records are lost. */
		a->next = 0;
	}
	return 0;
}

static int partlog_setup_blk(struct partlog_area *a)
{
	const char *spec = env_get("partlog_part");
	char *copy, *dev_str, *part_str;
	int devnum, ret;

	if (!spec || !*spec)
		spec = "0:minidump";
	copy = strdup(spec);
	if (!copy)
		return -ENOMEM;
	dev_str = copy;
	part_str = strchr(copy, ':');
	if (part_str)
		*part_str++ = '\0';
	devnum = dev_str[0] ? dectoul(dev_str, NULL) : 0;

	a->desc = blk_get_dev("scsi", devnum);
	if (!a->desc) {
		printf("partlog: scsi device %d not found (is UFS up?)\n",
		       devnum);
		free(copy);
		return -ENODEV;
	}
	if (!part_str || !*part_str)
		part_str = "minidump";
	if (isdigit(part_str[0])) {
		ret = part_get_info(a->desc, dectoul(part_str, NULL), &a->info);
	} else {
		ret = part_get_info_by_name(a->desc, part_str, &a->info);
	}
	free(copy);
	if (ret < 0) {
		printf("partlog: partition '%s' not found on scsi %d\n",
		       part_str, devnum);
		return -ENODEV;
	}
	a->blksz = a->desc->blksz;
	a->blocks = a->info.size;
	a->ram = false;
	return 0;
}

static int partlog_setup_ram(struct partlog_area *a)
{
	a->ram_base = env_get_hex("partlog_ram_addr", PARTLOG_RAM_DEFAULT_ADDR);
	a->ram_size = env_get_hex("partlog_ram_size", PARTLOG_RAM_DEFAULT_SIZE);
	a->blksz = 512;
	a->blocks = a->ram_size / a->blksz;
	a->ram = true;
	return 0;
}

static int partlog_setup(struct partlog_area *a, bool ram)
{
	int ret = ram ? partlog_setup_ram(a) : partlog_setup_blk(a);

	if (ret)
		return ret;
	return partlog_scan(a);
}

static int partlog_append(struct partlog_area *a, const void *data, u32 len)
{
	struct partlog_hdr *h;
	void *buf;
	ulong total;
	int ret = CMD_RET_FAILURE;

	if (!len || len > PARTLOG_MAX_PAYLOAD) {
		printf("partlog: bad length %u (max %d)\n", len,
		       PARTLOG_MAX_PAYLOAD);
		return CMD_RET_USAGE;
	}
	total = (PARTLOG_HDR_BLKS + DIV_ROUND_UP(len, a->blksz)) * a->blksz;
	if (a->next + total / a->blksz > a->blocks) {
		printf("partlog: area full (next=%lu of %lu blocks)\n",
		       a->next, a->blocks);
		return CMD_RET_FAILURE;
	}
	buf = memalign(64, total);
	if (!buf)
		return CMD_RET_FAILURE;
	memset(buf, 0, total);
	h = buf;
	memcpy(h->magic, PARTLOG_MAGIC, PARTLOG_MAGIC_LEN);
	h->seq = a->next_seq;
	h->len = len;
	h->crc32 = crc32(0, data, len);
	h->hdr_crc = crc32(0, (uchar *)buf, sizeof(*h));
	memcpy(buf + a->blksz, data, len);

	partlog_warn(a);
	if (partlog_write_blk(a, a->next, buf, total / a->blksz)) {
		printf("partlog: write failed\n");
		goto out;
	}
	printf("partlog: record #%u, %u bytes at block %lu\n",
	       h->seq, len, a->next);
	a->next += total / a->blksz;
	a->next_seq++;
	ret = CMD_RET_SUCCESS;
out:
	free(buf);
	return ret;
}

static int do_partlog_write(struct cmd_tbl *cmdtp, int flag, int argc,
			    char *const argv[], bool ram)
{
	struct partlog_area a;
	void *addr;
	ulong len;

	if (argc < 2)
		return CMD_RET_USAGE;
	addr = (void *)hextoul(argv[0], NULL);
	len = hextoul(argv[1], NULL);
	if (partlog_setup(&a, ram))
		return CMD_RET_FAILURE;
	return partlog_append(&a, addr, len);
}

static int do_partlog_print(struct cmd_tbl *cmdtp, int flag, int argc,
			    char *const argv[], bool ram)
{
	struct partlog_area a;
	char *text;
	int i, len = 0;

	if (argc < 1)
		return CMD_RET_USAGE;
	for (i = 0; i < argc; i++)
		len += strlen(argv[i]) + 1;
	text = malloc(len + 1);
	if (!text)
		return CMD_RET_FAILURE;
	text[0] = '\0';
	for (i = 0; i < argc; i++) {
		strcat(text, argv[i]);
		strcat(text, i == argc - 1 ? "\n" : " ");
	}
	if (partlog_setup(&a, ram)) {
		free(text);
		return CMD_RET_FAILURE;
	}
	i = partlog_append(&a, text, strlen(text));
	free(text);
	return i;
}

static int do_partlog_dump(struct cmd_tbl *cmdtp, int flag, int argc,
			   char *const argv[], bool ram)
{
	struct partlog_area a;
	struct partlog_hdr *h;
	ulong blk = 0, max_rec = 32;
	void *payload;
	int count = 0;

	if (argc >= 1)
		max_rec = dectoul(argv[0], NULL);
	if (partlog_setup(&a, ram))
		return CMD_RET_FAILURE;
	h = malloc(a.blksz);
	if (!h)
		return CMD_RET_FAILURE;
	while (blk < a.blocks && count < max_rec) {
		if (partlog_read_blk(&a, blk, h, 1) || !partlog_hdr_valid(h))
			break;
		payload = malloc(h->len + 1);
		if (!payload)
			break;
		if (partlog_read_blk(&a, blk + PARTLOG_HDR_BLKS, payload,
				     DIV_ROUND_UP(h->len, a.blksz))) {
			free(payload);
			break;
		}
		((char *)payload)[h->len] = '\0';
		printf("--- #%u @blk %lu, %u bytes, crc %08x%s\n",
		       h->seq, blk, h->len, h->crc32,
		       crc32(0, payload, h->len) == h->crc32 ?
		       "" : " [CRC BAD]");
		printf("%s%s", (char *)payload,
		       h->len && ((char *)payload)[h->len - 1] == '\n' ?
		       "" : "\n");
		free(payload);
		blk += PARTLOG_HDR_BLKS + DIV_ROUND_UP(h->len, a.blksz);
		count++;
	}
	free(h);
	if (!count)
		printf("partlog: no valid records\n");
	return CMD_RET_SUCCESS;
}

static int do_partlog_info(struct cmd_tbl *cmdtp, int flag, int argc,
			   char *const argv[], bool ram)
{
	struct partlog_area a;

	if (partlog_setup(&a, ram))
		return CMD_RET_FAILURE;
	if (ram) {
		printf("partlog: RAM ring at 0x%lx, size 0x%lx\n",
		       a.ram_base, a.ram_size);
	} else {
		printf("partlog: partition '%s' on scsi %d, start 0x%lx, "
		       "size 0x%lx blocks (%u-byte)\n", a.info.name,
		       a.desc->devnum, (ulong)a.info.start,
		       (ulong)a.info.size, a.blksz);
	}
	printf("partlog: next free block %lu, next seq %u\n",
	       a.next, a.next_seq);
	return CMD_RET_SUCCESS;
}

static int do_partlog_erase(struct cmd_tbl *cmdtp, int flag, int argc,
			    char *const argv[], bool ram)
{
	struct partlog_area a;
	void *zero;

	if (partlog_setup(&a, ram))
		return CMD_RET_FAILURE;
	zero = calloc(1, a.blksz);
	if (!zero)
		return CMD_RET_FAILURE;
	partlog_warn(&a);
	/* wipe the first block: the scanner stops there on next boot */
	if (partlog_write_blk(&a, 0, zero, 1)) {
		printf("partlog: erase failed\n");
		free(zero);
		return CMD_RET_FAILURE;
	}
	free(zero);
	printf("partlog: log area invalidated\n");
	return CMD_RET_SUCCESS;
}

static int do_partlog_console(struct cmd_tbl *cmdtp, int flag, int argc,
			      char *const argv[], bool ram)
{
	struct partlog_area a;

	if (partlog_setup(&a, ram))
		return CMD_RET_FAILURE;

#if CONFIG_IS_ENABLED(CONSOLE_RECORD)
	/*
	 * Drain the whole console recording buffer (CONFIG_CONSOLE_RECORD,
	 * enabled on liuqin so the boot log survives a failed boot) into the
	 * log area. membuff_getraw() may return the data in two installments.
	 */
	while (1) {
		char *data;
		int len;

		len = membuff_getraw((struct membuff *)&gd->console_out,
				     PARTLOG_MAX_PAYLOAD, true, &data);
		if (len <= 0)
			break;
		if (partlog_append(&a, data, (u32)len))
			return CMD_RET_FAILURE;
	}
	return CMD_RET_SUCCESS;
#else
	printf("partlog: console recording is disabled "
	       "(CONFIG_CONSOLE_RECORD)\n");
	return CMD_RET_FAILURE;
#endif
}

static int do_partlog(struct cmd_tbl *cmdtp, int flag, int argc,
		      char *const argv[])
{
	bool ram = false;
	const char *op;

	if (argc < 2)
		return CMD_RET_USAGE;
	argc--;
	argv++;
	if (!strcmp(argv[0], "ram")) {
		ram = true;
		argc--;
		argv++;
		if (argc < 1)
			return CMD_RET_USAGE;
	}
	op = argv[0];
	argc--;
	argv++;
	if (!strcmp(op, "write"))
		return do_partlog_write(cmdtp, flag, argc, argv, ram);
	if (!strcmp(op, "print"))
		return do_partlog_print(cmdtp, flag, argc, argv, ram);
	if (!strcmp(op, "console"))
		return do_partlog_console(cmdtp, flag, argc, argv, ram);
	if (!strcmp(op, "dump"))
		return do_partlog_dump(cmdtp, flag, argc, argv, ram);
	if (!strcmp(op, "info"))
		return do_partlog_info(cmdtp, flag, argc, argv, ram);
	if (!strcmp(op, "erase"))
		return do_partlog_erase(cmdtp, flag, argc, argv, ram);
	return CMD_RET_USAGE;
}

U_BOOT_CMD(
	partlog, 7, 0, do_partlog,
	"append log records to a raw partition or RAM ring",
	"write <addr> <len>   - append raw buffer to the log partition\n"
	"partlog print <text...> - append a text line to the log partition\n"
	"partlog console      - append the recorded console log "
	"(CONFIG_CONSOLE_RECORD)\n"
	"partlog dump [n]     - print up to n stored records (default 32)\n"
	"partlog info         - show target area and append position\n"
	"partlog erase        - invalidate the log area (wipes first block)\n"
	"partlog ram <op> ... - same operations on the RAM ring buffer\n"
	"                       (partlog_ram_addr/partlog_ram_size, defaults\n"
	"                       0xa7000000 / 4 MiB)\n"
	"Target partition: env partlog_part=<dev>:<part#|name> "
	"(default 0:minidump)"
);
