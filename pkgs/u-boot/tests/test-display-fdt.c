// SPDX-License-Identifier: GPL-2.0+
#include <assert.h>
#include <errno.h>
#include <libfdt.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "display-handoff.h"

static bool fail_malloc;
void *__real_malloc(size_t n);
void *__wrap_malloc(size_t n)
{
	return fail_malloc ? NULL : __real_malloc(n);
}

static unsigned char source[16384], scratch[16384], original[16384];

static int node(const void *fdt, const char *path)
{
	int n = fdt_path_offset(fdt, path);

	assert(n >= 0);
	return n;
}

static void prop(const char *path, const char *key, const char *value)
{
	assert(!fdt_setprop_string(source, node(source, path), key, value));
}

static void tree(const char *stdout, const char *args)
{
	const fdt32_t reg[] = {
		cpu_to_fdt32(0), cpu_to_fdt32(0xb8000000),
		cpu_to_fdt32(0), cpu_to_fdt32(0x2b00000),
	};

	memset(source, 0, sizeof(source));
	assert(!fdt_create_empty_tree(source, sizeof(source)));
	prop("/", "compatible", "xiaomi,liuqin");
	assert(fdt_add_subnode(source, 0, "reserved-memory") >= 0);
	assert(fdt_add_subnode(source, node(source, "/reserved-memory"), "linux_splash@b8000000") >= 0);
	assert(!fdt_setprop(source, node(source, "/reserved-memory/linux_splash@b8000000"), "reg", reg, sizeof(reg)));
	assert(!fdt_setprop(source, node(source, "/reserved-memory/linux_splash@b8000000"), "no-map", NULL, 0));
	assert(fdt_add_subnode(source, 0, "chosen") >= 0);
	assert(fdt_add_subnode(source, node(source, "/chosen"), "framebuffer@b8000000") >= 0);
	prop("/chosen/framebuffer@b8000000", "compatible", "simple-framebuffer");
	assert(fdt_add_subnode(source, 0, "serial@1234") >= 0);
	prop("/serial@1234", "compatible", "ns16550a");
	assert(fdt_add_subnode(source, 0, "aliases") >= 0);
	prop("/aliases", "display0", "/chosen/framebuffer@b8000000");
	prop("/aliases", "serial0", "/serial@1234");
	prop("/chosen", "stdout-path", stdout);
	prop("/chosen", "bootargs", args);
}

static int run(void)
{
	int ret;

	memcpy(original, source, sizeof(source));
	ret = liuqin_display_fdt(source, scratch, fdt_totalsize(source));
	assert(!memcmp(original, source, sizeof(source))); /* always transactional */
	return ret;
}

static const char *get(const char *path, const char *key)
{
	int len;
	const char *s = fdt_getprop(scratch, node(scratch, path), key, &len);

	assert(s && len > 0 && !s[len - 1]);
	assert(strlen(s) == (size_t)len - 1);
	return s;
}

int main(void)
{
	int chosen, len;
	const void *a, *b;

	tree("display0:1800x2880", "earlycon=simplefb console=tty0 earlycon rootwait foo=\"two  earlycon=simplefb words\" earlycon=simplefb2 earlycon=simplefb,0xb8000000");
	prop("/chosen", "linux,stdout-path", "/chosen/framebuffer@b8000000");
	assert(!run());
	assert(!strcmp(get("/chosen", "bootargs"),
		       "console=tty0 rootwait foo=\"two  earlycon=simplefb words\" earlycon=simplefb2"));
	assert(!strcmp(get("/chosen", "liuqin,display-handoff"), "quiesced-v1"));
	chosen = node(scratch, "/chosen");
	assert(!fdt_getprop(scratch, chosen, "stdout-path", &len));
	assert(!fdt_getprop(scratch, chosen, "linux,stdout-path", &len));
	assert(fdt_node_offset_by_compatible(scratch, -1, "simple-framebuffer") == -FDT_ERR_NOTFOUND);
	a = fdt_getprop(source, node(source, "/reserved-memory/linux_splash@b8000000"), "reg", &len);
	b = fdt_getprop(scratch, node(scratch, "/reserved-memory/linux_splash@b8000000"), "reg", NULL);
	assert(b && len == 16 && !memcmp(a, b, len));
	assert(fdt_getprop(scratch, node(scratch, "/reserved-memory/linux_splash@b8000000"), "no-map", &len));
	assert(len == 0);
	assert(!fdt_check_full(scratch, sizeof(scratch)));

	tree("serial0:115200n8", "earlycon=simplefb console=tty0 earlycon");
	assert(!run());
	assert(!strcmp(get("/chosen", "stdout-path"), "serial0:115200n8"));
	assert(!strcmp(get("/chosen", "bootargs"), "console=tty0 earlycon"));
	/* Reapplying the metadata fixup is also safe. */
	memcpy(source, scratch, sizeof(source));
	assert(!run());

	tree("display0", "earlycon=simplefb");
	assert(!run() && !strcmp(get("/chosen", "bootargs"), ""));
	tree("display0", " \t earlycon=simplefb \t rootwait\t ");
	assert(!run() && !strcmp(get("/chosen", "bootargs"), "rootwait"));

	tree("display0", "earlycon=simplefb");
	fail_malloc = true;
	assert(run() == -ENOMEM);
	fail_malloc = false;
	prop("/", "compatible", "qcom,other-board");
	assert(run() == -FDT_ERR_BADVALUE);
	/* The runtime control-DT identity policy must not weaken validation of
	 * the fresh Linux FDT loaded from disk. These are separate trees. */
	tree("display0", "earlycon=simplefb");
	{
		static const char cape[] = "qcom,cape-mtp\0qcom,cape\0qcom,mtp";

		assert(!fdt_setprop(source, 0, "compatible", cape, sizeof(cape)));
		assert(run() == -FDT_ERR_BADVALUE);
	}
	tree("display0", "earlycon=simplefb");
	assert(!fdt_setprop(source, node(source, "/chosen"), "bootargs", "bad", 3));
	assert(run() == -FDT_ERR_BADVALUE);
	tree("display0", "earlycon=simplefb");
	assert(!fdt_setprop(source, node(source, "/chosen"), "stdout-path", "bad", 3));
	assert(run() == -FDT_ERR_BADVALUE);
	tree("serial0", "rootwait");
	assert(!fdt_del_node(source, node(source, "/chosen/framebuffer@b8000000")));
	assert(!fdt_pack(source)); /* No room for the handoff contract marker. */
	assert(run() == -FDT_ERR_NOSPACE);
	fdt_set_magic(source, 0);
	assert(run() == -FDT_ERR_BADMAGIC);
	puts("Linux FDT: aliases, stdout, cmdline, reservation, allocation/space/validation failures passed");
	return 0;
}
