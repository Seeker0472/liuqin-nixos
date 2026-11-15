// SPDX-License-Identifier: GPL-2.0+
/* This operates on the loaded Linux FDT, never gd->fdt_blob / OF_LIVE. */
#include <errno.h>
#include <malloc.h>
#include <linux/libfdt.h>
#include <linux/string.h>

#include "display-handoff.h"

static bool simplefb_arg(const char *arg, unsigned int len, bool fb_stdout)
{
	static const char prefix[] = "earlycon=simplefb";
	unsigned int n = sizeof(prefix) - 1;

	return (len >= n && !memcmp(arg, prefix, n) &&
		(len == n || arg[n] == ',')) ||
	       (fb_stdout && len == 8 && !memcmp(arg, "earlycon", 8));
}

static int fix_bootargs(void *fdt, int chosen, bool fb_stdout)
{
	const char *args;
	char *copy, *dst;
	unsigned int pos, start;
	int len, ret;

	args = fdt_getprop(fdt, chosen, "bootargs", &len);
	if (!args)
		return len == -FDT_ERR_NOTFOUND ? 0 : len;
	if (len < 1 || args[len - 1] || (int)strlen(args) != len - 1)
		return -FDT_ERR_BADVALUE;
	copy = malloc(len);
	if (!copy)
		return -ENOMEM;
	dst = copy;
	for (pos = 0; pos < (unsigned int)len - 1; ) {
		bool quoted = false;

		while (args[pos] == ' ' || args[pos] == '\t')
			pos++;
		start = pos;
		while (args[pos]) {
			if (args[pos] == '"')
				quoted = !quoted;
			if (!quoted && (args[pos] == ' ' || args[pos] == '\t'))
				break;
			pos++;
		}
		if (pos == start || simplefb_arg(args + start, pos - start, fb_stdout))
			continue;
		if (dst != copy)
			*dst++ = ' ';
		memcpy(dst, args + start, pos - start);
		dst += pos - start;
	}
	*dst = 0;
	ret = fdt_setprop_string(fdt, chosen, "bootargs", copy);
	free(copy);
	return ret;
}

/* Resolve aliases and the :options suffix before deleting any nodes. */
static int fix_stdout(void *fdt, int chosen, const char *property, bool *fb)
{
	const char *path;
	int len, n, node;

	path = fdt_getprop(fdt, chosen, property, &len);
	if (!path)
		return len == -FDT_ERR_NOTFOUND ? 0 : len;
	if (len < 1 || path[len - 1] || (int)strlen(path) != len - 1)
		return -FDT_ERR_BADVALUE;
	for (n = 0; path[n] && path[n] != ':'; n++)
		;
	node = fdt_path_offset_namelen(fdt, path, n);
	if (node >= 0 && !fdt_node_check_compatible(fdt, node, "simple-framebuffer")) {
		*fb = true;
		return fdt_delprop(fdt, chosen, property);
	}
	return 0;
}

int liuqin_display_fdt(const void *source, void *scratch, unsigned int capacity)
{
	bool fb_stdout = false;
	int ret, node, chosen;

	/* Caller retains the source until every operation, including hardware
	 * commit, has succeeded. No target-tree allocation after display off. */
	ret = fdt_check_full(source, capacity);
	if (ret)
		return ret;
	if (fdt_node_check_compatible(source, 0, "xiaomi,liuqin"))
		return -FDT_ERR_BADVALUE;
	ret = fdt_open_into(source, scratch, capacity);
	if (ret)
		return ret;
	chosen = fdt_path_offset(scratch, "/chosen");
	if (chosen < 0)
		return chosen;
	ret = fix_stdout(scratch, chosen, "stdout-path", &fb_stdout);
	if (!ret)
		ret = fix_stdout(scratch, chosen, "linux,stdout-path", &fb_stdout);
	if (!ret)
		ret = fix_bootargs(scratch, chosen, fb_stdout);
	if (ret)
		return ret;
	/* No simplefb consumer can truthfully claim a stopped scanout pipeline.
	 * Reserved memory is deliberately retained, including the stage log. */
	while ((node = fdt_node_offset_by_compatible(scratch, -1,
						   "simple-framebuffer")) >= 0) {
		ret = fdt_del_node(scratch, node);
		if (ret)
			return ret;
	}
	if (node != -FDT_ERR_NOTFOUND)
		return node;
	chosen = fdt_path_offset(scratch, "/chosen");
	return fdt_setprop_string(scratch, chosen, "liuqin,display-handoff", "quiesced-v1");
}
