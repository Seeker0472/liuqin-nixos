// SPDX-License-Identifier: MIT
/* Mark liuqin's GPT-backed Qualcomm slot A successful, fail closed. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/fs.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>

#define SECTOR_SIZE 4096ULL
#define DISK_BYTES 2923429888ULL
#define ENTRY_COUNT 96U
#define ENTRY_SIZE 128U
#define HEADER_SIZE 92U
#define BOOT_A_FIRST 75014ULL
#define BOOT_A_LAST 124165ULL
#define ATTR_PRIORITY_MASK (3ULL << 48)
#define ATTR_ACTIVE (1ULL << 50)
#define ATTR_TRIES_MASK (7ULL << 51)
#define ATTR_SUCCESSFUL (1ULL << 54)
#define ATTR_UNBOOTABLE (1ULL << 55)

static uint32_t le32(const unsigned char *p)
{
	return (uint32_t)p[0] | (uint32_t)p[1] << 8 |
	       (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static uint64_t le64(const unsigned char *p)
{
	return (uint64_t)le32(p) | (uint64_t)le32(p + 4) << 32;
}

static void put_le32(unsigned char *p, uint32_t v)
{
	p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24;
}

static void put_le64(unsigned char *p, uint64_t v)
{
	put_le32(p, (uint32_t)v);
	put_le32(p + 4, (uint32_t)(v >> 32));
}

static uint32_t crc32_bytes(const unsigned char *buf, size_t len)
{
	uint32_t crc = ~0U;
	size_t i;
	int bit;

	for (i = 0; i < len; i++) {
		crc ^= buf[i];
		for (bit = 0; bit < 8; bit++)
			crc = (crc >> 1) ^ (0xedb88320U & (0U - (crc & 1U)));
	}
	return ~crc;
}

static int full_pread(int fd, void *buf, size_t len, off_t off)
{
	unsigned char *p = buf;
	while (len) {
		ssize_t n = pread(fd, p, len, off);
		if (n <= 0)
			return -1;
		p += n; off += n; len -= (size_t)n;
	}
	return 0;
}

static int full_pwrite(int fd, const void *buf, size_t len, off_t off)
{
	const unsigned char *p = buf;
	while (len) {
		ssize_t n = pwrite(fd, p, len, off);
		if (n <= 0)
			return -1;
		p += n; off += n; len -= (size_t)n;
	}
	return 0;
}

static int name_is(const unsigned char *entry, const char *name)
{
	size_t i, len = strlen(name);
	if (len > 35)
		return 0;
	for (i = 0; i < len; i++)
		if (entry[56 + i * 2] != (unsigned char)name[i] || entry[57 + i * 2])
			return 0;
	return entry[56 + len * 2] == 0 && entry[57 + len * 2] == 0;
}

struct gpt_copy {
	unsigned char header[SECTOR_SIZE];
	unsigned char entries[ENTRY_COUNT * ENTRY_SIZE];
	uint64_t header_lba;
	uint64_t entries_lba;
};

static int load_gpt_copy(int fd, uint64_t disk_lbas, uint64_t header_lba,
			 struct gpt_copy *g, int allow_stale_entries_crc)
{
	uint32_t saved_header_crc, saved_entries_crc;
	unsigned char check[SECTOR_SIZE];

	memset(g, 0, sizeof(*g));
	g->header_lba = header_lba;
	if (full_pread(fd, g->header, sizeof(g->header), header_lba * SECTOR_SIZE))
		return -1;
	if (memcmp(g->header, "EFI PART", 8) || le32(g->header + 12) != HEADER_SIZE ||
	    le64(g->header + 24) != header_lba ||
	    le64(g->header + 32) != (header_lba == 1 ? disk_lbas - 1 : 1) ||
	    le64(g->header + 40) != 6 || le64(g->header + 48) != disk_lbas - 6 ||
	    le32(g->header + 80) != ENTRY_COUNT || le32(g->header + 84) != ENTRY_SIZE)
		return -1;
	saved_header_crc = le32(g->header + 16);
	memcpy(check, g->header, sizeof(check));
	memset(check + 16, 0, 4);
	if (crc32_bytes(check, HEADER_SIZE) != saved_header_crc)
		return -1;
	g->entries_lba = le64(g->header + 72);
	if (g->entries_lba != (header_lba == 1 ? 2 : disk_lbas - 5))
		return -1;
	if (full_pread(fd, g->entries, sizeof(g->entries), g->entries_lba * SECTOR_SIZE))
		return -1;
	saved_entries_crc = le32(g->header + 88);
	if (crc32_bytes(g->entries, sizeof(g->entries)) != saved_entries_crc &&
	    !allow_stale_entries_crc)
		return -1;
	return 0;
}

static unsigned char *find_boot_a(struct gpt_copy *g)
{
	unsigned int i;
	for (i = 0; i < ENTRY_COUNT; i++) {
		unsigned char *e = g->entries + i * ENTRY_SIZE;
		if (!name_is(e, "boot_a"))
			continue;
		if (le64(e + 32) != BOOT_A_FIRST || le64(e + 40) != BOOT_A_LAST)
			return NULL;
		return e;
	}
	return NULL;
}

static void refresh_crcs(struct gpt_copy *g)
{
	put_le32(g->header + 88, crc32_bytes(g->entries, sizeof(g->entries)));
	put_le32(g->header + 16, 0);
	put_le32(g->header + 16, crc32_bytes(g->header, HEADER_SIZE));
}

static int cmdline_is_slot_a(void)
{
	char buf[8192];
	int fd = open("/proc/cmdline", O_RDONLY | O_CLOEXEC);
	ssize_t n;
	if (fd < 0)
		return 0;
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0)
		return 0;
	buf[n] = 0;
	return strstr(buf, "androidboot.slot_suffix=_a") != NULL;
}

static int sde_is_unmounted(void)
{
	char line[1024];
	FILE *f = fopen("/proc/mounts", "re");
	if (!f)
		return 0;
	while (fgets(line, sizeof(line), f)) {
		if (!strncmp(line, "/dev/sde", 8)) {
			fclose(f);
			return 0;
		}
	}
	fclose(f);
	return 1;
}

int main(int argc, char **argv)
{
	const char *path = "/dev/sde";
	int testing = 0, mark = 1, made_rw = 0, fd = -1, ro = 1, zero = 0, one = 1, rc = 1;
	uint64_t bytes = 0, disk_lbas, attrs;
	struct stat st;
	struct gpt_copy primary, backup, verify_primary, verify_backup;
	unsigned char *pa, *ba, *vpa, *vba;

	if (argc == 2 && (!strcmp(argv[1], "--mark-a") || !strcmp(argv[1], "--check-a"))) {
		mark = !strcmp(argv[1], "--mark-a");
		if (!cmdline_is_slot_a() || !sde_is_unmounted()) {
			fprintf(stderr, "liuqin-slot-success: current slot/mount guard failed\n");
			return 1;
		}
	} else if (argc == 3 &&
		   (!strcmp(argv[1], "--test-image") ||
		    !strcmp(argv[1], "--test-image-check")) &&
		   getenv("LIUQIN_SLOT_SUCCESS_TESTING") &&
		   !strcmp(getenv("LIUQIN_SLOT_SUCCESS_TESTING"), "unsafe-mock-only")) {
		testing = 1;
		mark = !strcmp(argv[1], "--test-image");
		path = argv[2];
	} else {
		fprintf(stderr, "usage: liuqin-mark-slot-successful --mark-a|--check-a\n");
		return 2;
	}

	if (lstat(path, &st) || (!testing && !S_ISBLK(st.st_mode)) ||
	    (testing && !S_ISREG(st.st_mode)))
		goto out;
	fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		goto out;
	if (testing) {
		bytes = (uint64_t)st.st_size;
	} else {
		int logical = 0;
		if (ioctl(fd, BLKGETSIZE64, &bytes) || ioctl(fd, BLKSSZGET, &logical) ||
		    ioctl(fd, BLKROGET, &ro) || bytes != DISK_BYTES ||
		    logical != (int)SECTOR_SIZE || ro != 1)
			goto out;
	}
	if (bytes != DISK_BYTES || bytes % SECTOR_SIZE)
		goto out;
	disk_lbas = bytes / SECTOR_SIZE;
	if (load_gpt_copy(fd, disk_lbas, 1, &primary, 0) ||
	    load_gpt_copy(fd, disk_lbas, disk_lbas - 1, &backup, 1) ||
	    memcmp(primary.header + 56, backup.header + 56, 16))
		goto out;
	pa = find_boot_a(&primary);
	if (!pa || !find_boot_a(&backup))
		goto out;
	/* Qualcomm fastboot/ABL updates backup entries but can leave the backup
	 * header's entry CRC stale.  A fully valid primary GPT is authoritative;
	 * rebuild the backup array from it rather than merging untrusted attrs. */
	memcpy(backup.entries, primary.entries, sizeof(primary.entries));
	ba = find_boot_a(&backup);
	attrs = le64(pa + 48);
	if ((attrs & ATTR_PRIORITY_MASK) != ATTR_PRIORITY_MASK || !(attrs & ATTR_ACTIVE) ||
	    (!(attrs & ATTR_TRIES_MASK) && !(attrs & ATTR_SUCCESSFUL)))
		goto out;
	if (!mark) {
		if (!(attrs & ATTR_SUCCESSFUL) || (attrs & ATTR_UNBOOTABLE))
			goto out;
		rc = 0;
		goto out;
	}
	attrs |= ATTR_SUCCESSFUL;
	attrs &= ~ATTR_UNBOOTABLE;
	put_le64(pa + 48, attrs);
	put_le64(ba + 48, attrs);
	refresh_crcs(&primary);
	refresh_crcs(&backup);

	if (!testing) {
		if (ioctl(fd, BLKROSET, &zero))
			goto out;
		made_rw = 1;
		close(fd);
		fd = -1;
		fd = open(path, O_RDWR | O_CLOEXEC | O_SYNC);
		if (fd < 0)
			goto out;
	} else {
		close(fd);
		fd = open(path, O_RDWR | O_CLOEXEC | O_SYNC);
		if (fd < 0)
			goto out;
	}
	/* Backup GPT first: a power loss always leaves at least one old/new copy. */
	if (full_pwrite(fd, backup.entries, sizeof(backup.entries), backup.entries_lba * SECTOR_SIZE) ||
	    full_pwrite(fd, backup.header, sizeof(backup.header), backup.header_lba * SECTOR_SIZE) || fsync(fd) ||
	    full_pwrite(fd, primary.entries, sizeof(primary.entries), primary.entries_lba * SECTOR_SIZE) ||
	    full_pwrite(fd, primary.header, sizeof(primary.header), primary.header_lba * SECTOR_SIZE) || fsync(fd))
		goto out;
	if (load_gpt_copy(fd, disk_lbas, 1, &verify_primary, 0) ||
	    load_gpt_copy(fd, disk_lbas, disk_lbas - 1, &verify_backup, 0) ||
	    memcmp(verify_primary.entries, verify_backup.entries, sizeof(verify_primary.entries)))
		goto out;
	vpa = find_boot_a(&verify_primary);
	vba = find_boot_a(&verify_backup);
	if (!vpa || !vba || !(le64(vpa + 48) & ATTR_SUCCESSFUL) ||
	    (le64(vpa + 48) & ATTR_UNBOOTABLE) || le64(vpa + 48) != le64(vba + 48))
		goto out;
	rc = 0;

out:
	if (fd < 0 && made_rw)
		fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd >= 0) {
		if (!testing && made_rw && ioctl(fd, BLKROSET, &one))
			rc = 1;
		close(fd);
	}
	if (rc)
		fprintf(stderr, "liuqin-slot-success: refused or failed; GPT not accepted\n");
	else
		puts(mark ? "liuqin-slot-success: slot A is successful; primary/backup GPT CRCs verified" :
		     "liuqin-slot-success: slot A success is verified; primary/backup GPT CRCs valid");
	return rc;
}
