#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0+
"""Execute the patched production entry/exit functions with mocked providers.

Only the ARM entry assembly and DM/USB providers are mocked. Function bodies
come from the pinned, patched U-Boot source, so a misplaced hook fails here.
"""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile


def function(source, name):
    match = re.search(r"^(?:static )?(?:int|bool|void) " + name + r"\([^;]*?\)\n\{", source, re.M)
    if not match:
        raise AssertionError(f"missing production function {name}")
    end, depth = match.end(), 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[match.start():end]


def execute(code, name, extra=()):
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / (name + ".c")
        binary = source.with_suffix("")
        source.write_text(code)
        subprocess.run([os.environ.get("CC", "cc"), "-std=c11", "-Wall", "-Wextra",
                        "-Werror", "-Wno-unused-parameter", str(source), "-o", str(binary), *extra], check=True)
        subprocess.run([str(binary)], check=True)


root = Path(sys.argv[1])
bootm = (root / "arch/arm/lib/bootm.c").read_text()
boot_os = (root / "boot/bootm_os.c").read_text()
usb = (root / "cmd/fastboot.c").read_text()

execute(r'''
#include <assert.h>
#include <errno.h>
#include <stdio.h>
struct bootm_headers { struct { int os, type; } os; };
struct bootm_info { struct bootm_headers *images; };
typedef int boot_os_fn(int flag, struct bootm_info *bmi);
#define BOOTM_STATE_OS_BD_T 1
#define BOOTM_STATE_OS_CMDLINE 2
#define BOOTM_STATE_OS_PREP 4
#define BOOTM_STATE_OS_GO 8
#define BOOTM_STATE_OS_FAKE_GO 16
#define IH_OS_LINUX 5
#define IH_TYPE_STANDALONE 4
#define CONFIG_SANDBOX 0
#define IS_ENABLED(x) (x)
#define BOOTM_ERR_RESET (-1)
#define BOOTSTAGE_ID_BOOT_OS_RETURNED 0
#define debug(...) ((void)0)
static void bootstage_error(int unused) {}
static void arch_preboot_os(void) {}
static void board_preboot_os(void) {}
static int order[8], count, reject;
static void boot_prep_linux(struct bootm_headers *h) { order[count++] = 0; }
static int board_linux_handoff(struct bootm_headers *h) { order[count++] = 1; return reject; }
static void boot_jump_linux(struct bootm_headers *h, int flag) { order[count++] = 2; }
static void board_linux_handoff_returned(void) { order[count++] = 3; }
''' + function(bootm, "boot_go_linux") + "\n" + function(bootm, "do_bootm_linux") + "\n" + function(boot_os, "boot_selected_os") + r'''
int main(void)
{
    struct bootm_headers h = { .os = { .os = IH_OS_LINUX, .type = 1 } };
    struct bootm_info b = { &h };
    assert(!do_bootm_linux(BOOTM_STATE_OS_PREP, &b));
    assert(count == 1 && order[0] == 0);
    count = 0;
    assert(!boot_selected_os(BOOTM_STATE_OS_FAKE_GO, &b, do_bootm_linux));
    assert(count == 1 && order[0] == 2);
    count = 0;
    assert(boot_selected_os(BOOTM_STATE_OS_GO, &b, do_bootm_linux) == BOOTM_ERR_RESET);
    assert(count == 3 && order[0] == 1 && order[1] == 2 && order[2] == 3);
    count = 0;
    reject = -EIO;
    assert(boot_selected_os(BOOTM_STATE_OS_GO, &b, do_bootm_linux) == 1);
    assert(count == 1 && order[0] == 1); /* no generic device/CPU cleanup */
    count = 0;
    reject = -1; /* libfdt NOTFOUND must not become BOOTM_ERR_RESET */
    assert(boot_selected_os(BOOTM_STATE_OS_GO, &b, do_bootm_linux) == 1);
    assert(count == 1 && order[0] == 1);
    count = 0;
    reject = 0;
    assert(do_bootm_linux(BOOTM_STATE_OS_BD_T, &b) < 0 && !count);
    puts("boot_selected_os -> ARM: PREP, GO, FAKE_GO, safe rejection and kernel-return reset semantics passed");
}
''', "test-entry")

execute(r'''
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#define CONFIG_USB_FUNCTION_FASTBOOT 1
#define IS_ENABLED(x) (x)
#define CMD_RET_FAILURE 1
#define CMD_RET_USAGE 2
#define CMD_RET_SUCCESS 0
#define pr_err(...) ((void)0)
#define simple_strtoul strtoul
struct udevice { int unused; };
static struct udevice device;
static int hook, cleanup, cable = 1, init_error;
static int udc_device_get_by_index(int i, struct udevice **d) { *d = &device; return init_error; }
static void g_dnl_clear_detach(void) {}
static int g_dnl_register(const char *s) { return 0; }
static int g_dnl_board_usb_cable_connected(void) { return cable; }
static int g_dnl_detach(void) { return 1; }
static int ctrlc(void) { return 0; }
static void schedule(void) {}
static void dm_usb_gadget_handle_interrupts(struct udevice *d) {}
static void board_fastboot_exit(void) { assert(!cleanup); hook++; }
static void udc_device_put(struct udevice *d) { assert(hook == 1); cleanup++; }
static void g_dnl_unregister(void) { assert(hook == 1 && cleanup == 1); }
''' + function(usb, "do_fastboot_usb") + r'''
int main(void)
{
    char *args[] = { "usb", "0" };
    assert(!do_fastboot_usb(2, args, 0, 0) && hook == 1 && cleanup == 1);
    hook = cleanup = 0;
    cable = 0;
    assert(do_fastboot_usb(2, args, 0, 0) == CMD_RET_FAILURE && hook == 1 && cleanup == 1);
    hook = cleanup = 0;
    init_error = -1;
    assert(do_fastboot_usb(2, args, 0, 0) == CMD_RET_FAILURE && !hook && !cleanup);
    puts("USB exit: guard runs before provider teardown on normal and cable-abort paths");
}
''', "test-usb-exit")

geni = (root / "drivers/i2c/geni_i2c.c").read_text()
execute(r'''
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
typedef unsigned int u32;
#define M_GENI_CMD_ABORT (1U << 1)
#define M_CMD_ABORT_EN (1U << 5)
#define SE_GENI_M_CMD_CTRL_REG 0x604
#define SE_GENI_M_IRQ_STATUS 0x610
#define SE_GENI_M_IRQ_CLEAR 0x618
struct geni_i2c_priv { unsigned char *base; };
static unsigned char space[0x1000];
static unsigned int time_us, ready_at, clears;
static bool stuck;
static void writel(u32 v, void *p)
{
    if (p == space + SE_GENI_M_CMD_CTRL_REG) { assert(v == M_GENI_CMD_ABORT); return; }
    assert(p == space + SE_GENI_M_IRQ_CLEAR && v == M_CMD_ABORT_EN);
    clears++;
}
static u32 readl(void *p)
{
    assert(p == space + SE_GENI_M_IRQ_STATUS);
    return !stuck && time_us >= ready_at ? M_CMD_ABORT_EN : 0;
}
static void udelay(unsigned int us) { time_us += us; assert(time_us <= 1000000); }
''' + function(geni, "geni_i2c_abort") + r'''
int main(void)
{
    struct geni_i2c_priv g = { space };
    assert(!geni_i2c_abort(&g) && clears == 1);
    ready_at = 180;
    clears = 0;
    assert(!geni_i2c_abort(&g) && time_us == 180 && clears == 1);
    time_us = clears = 0;
    stuck = true;
    assert(geni_i2c_abort(&g) == -ETIMEDOUT && time_us == 1000000 && !clears);
    puts("GENI abort: immediate, delayed and stuck completion, correct IRQ_CLEAR passed");
}
''', "test-i2c-abort")

board = Path(__file__).parents[1] / "files/board/qualcomm/liuqin"
adapter = (board / "display.c").read_text()
start = adapter.index("static const struct {")
windows = adapter[start:adapter.index("};", start) + 2]
execute(r'''
#include <assert.h>
#include <errno.h>
#include <libfdt.h>
#include <setjmp.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "display-handoff.h"
#define IH_ARCH_ARM64 22
#define LIUQIN_PREFIX "test: "
#define MDSS_PATH "/soc@0/display-subsystem@ae00000"
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define __iomem
#define mb() ((void)0)
typedef uint64_t phys_addr_t;
typedef uint64_t fdt_size_t;
typedef unsigned int u32;
struct bootm_headers { struct { int arch; } os; unsigned long ep; void *ft_addr; unsigned long ft_len; };
static struct ldh handoff;
static jmp_buf recovery;
static unsigned char target[4096], before[4096];
static unsigned int allocations, commits, resources, capacity;
static bool no_memory, commit_failed;
static int resource_error, commit_error;
static uintptr_t mmio;
static u32 readl(void *p) { mmio = (uintptr_t)p; return 0; }
static void writel(u32 v, void *p) { mmio = (uintptr_t)p; }
static void display_init(void) {}
static int display_resources(void) { resources++; return resource_error; }
static void display_recover(void) { longjmp(recovery, 1); }
static void liuqin_stage(const char *s) {}
const char *ldh_stage_name(enum ldh_stage s) { return "test-stage"; }
int ldh_commit(struct ldh *h)
{
    assert(!memcmp(target, before, sizeof(target))); /* no premature FDT publication */
    commits++;
    if (h->state == LDH_QUIESCED) return 0;
    h->state = commit_error ? (commit_failed ? LDH_FAILED : LDH_BORROWED) : LDH_QUIESCED;
    return commit_error;
}
static void *test_malloc(size_t n) { allocations = n; return no_memory ? NULL : malloc(n); }
#define malloc test_malloc
''' + windows + "\n" + function(adapter, "display_read") + "\n" + function(adapter, "display_write") + "\n" + function(adapter, "terminal") + "\n" + function(adapter, "board_linux_handoff") + "\n" + function(adapter, "board_fastboot_exit") + r'''
#undef malloc
static struct bootm_headers setup(void)
{
    int chosen, fb;
    memset(target, 0, sizeof(target));
    assert(!fdt_create_empty_tree(target, sizeof(target)));
    assert(!fdt_setprop_string(target, 0, "compatible", "xiaomi,liuqin"));
    chosen = fdt_add_subnode(target, 0, "chosen");
    assert(chosen >= 0);
    assert(!fdt_setprop_string(target, chosen, "bootargs", "earlycon=simplefb rootwait"));
    fb = fdt_add_subnode(target, chosen, "framebuffer@b8000000");
    assert(fb >= 0);
    assert(!fdt_setprop_string(target, fb, "compatible", "simple-framebuffer"));
    assert(!fdt_pack(target));
    capacity = fdt_totalsize(target);
    memcpy(before, target, sizeof(target));
    handoff = (struct ldh){ .state = LDH_BORROWED };
    no_memory = commit_failed = false;
    resource_error = commit_error = 0;
    resources = commits = allocations = 0;
    return (struct bootm_headers){ .os = { IH_ARCH_ARM64 }, .ep = 0x80000000,
                                  .ft_addr = target, .ft_len = 4096 };
}
int main(void)
{
    struct bootm_headers image;
    unsigned int value;
    image = setup();
    assert(!board_linux_handoff(&image));
    assert(image.ft_len == capacity && allocations == capacity);
    assert(commits == 1 && resources == 1);
    assert(!memcmp(target + capacity, before + capacity, sizeof(target) - capacity));
    assert(fdt_getprop(target, fdt_path_offset(target, "/chosen"), "liuqin,display-handoff", NULL));
    image = setup();
    image.ft_len = 32; /* Old input size may also be smaller than final blob. */
    assert(!board_linux_handoff(&image) && image.ft_len == capacity);
    image = setup();
    no_memory = true;
    assert(board_linux_handoff(&image) == -ENOMEM && !commits);
    assert(!memcmp(target, before, sizeof(target)));
    image = setup();
    resource_error = -ENODEV;
    assert(board_linux_handoff(&image) == -ENODEV && !commits);
    image = setup();
    commit_error = -EIO;
    assert(board_linux_handoff(&image) == -EIO && commits == 1);
    assert(!memcmp(target, before, sizeof(target)));
    image = setup();
    commit_error = -EIO;
    commit_failed = true;
    if (!setjmp(recovery)) { board_linux_handoff(&image); assert(0); }
    assert(handoff.state == LDH_FAILED && !memcmp(target, before, sizeof(target)));
    image = setup();
    handoff.state = LDH_QUIESCED;
    image.os.arch = 0;
    if (!setjmp(recovery)) { board_linux_handoff(&image); assert(0); }
    image = setup();
    handoff.state = LDH_QUIESCED;
    assert(!board_linux_handoff(&image) && !resources);
    if (!setjmp(recovery)) { board_fastboot_exit(); assert(0); }
    handoff.state = LDH_BORROWED;
    board_fastboot_exit(); /* returning to menu remains possible before commit */
    assert(!display_read(NULL, LDH_MDSS, 0, &value) && mmio == 0xae00000);
    assert(!display_read(NULL, LDH_DPU, 0x35000, &value) && mmio == 0xae36000);
    assert(!display_read(NULL, LDH_DSI0, 4, &value) && mmio == 0xae94004);
    assert(!display_write(NULL, LDH_PHY1, 0x3c, 0) && mmio == 0xae9643c);
    assert(display_read(NULL, LDH_DSI0, 0x400, &value) == -EINVAL);
    assert(display_write(NULL, LDH_PHY0, 1, 0) == -EINVAL);
    puts("board adapter: final FDT capacity/publication, terminal recovery and raw MMIO windows passed");
}
''', "test-board-adapter", ["-I", str(board), "-I", str(Path(__file__).parent / "include"),
                           str(board / "display-fdt.c"), "-lfdt"])

# The adapter tests above stub provider acquisition. Exercise the REAL resource
# checker and report separately, including every early-return boundary.
resource_start = adapter.index("/* Cache the metadata checks")
resource_defs = adapter[resource_start:adapter.index("static int display_read", resource_start)]
execute(r'''
#include <assert.h>
#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "display-handoff.h"
#define MDSS_PATH "/soc@0/display-subsystem@ae00000"
#define BIAS_BUS "/soc@0/geniqup@9c0000/i2c@984000"
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define BIT(n) (1U << (n))
#define UCLASS_I2C 1
#define FDT_ADDR_T_NONE UINT64_MAX
#define FDT_SIZE_T_NONE UINT64_MAX
typedef uint64_t phys_addr_t;
typedef uint64_t fdt_addr_t;
typedef uint64_t fdt_size_t;
typedef int ofnode;
typedef unsigned int u32;
struct udevice { int unused; };
static struct udevice bus_device, chip_device, *bias_chip;
static struct ldh handoff;
static const struct ldh_io display_io;
static unsigned int nodes, bus_calls, chip_calls;
static int bus_error, chip_error;
static bool config_exists, config_enabled, config_compatible, bus_exists, bus_enabled;
static fdt_addr_t addresses[8];
static fdt_size_t sizes[8];
static char rows[32][60];
static unsigned int row_count;
static char compatible[3][80];
static void display_init(void) {}
static void fastboot_fail(const char *message, char *response) { snprintf(response, 64, "FAIL%s", message); }
static void fastboot_okay(const char *message, char *response) { snprintf(response, 64, "OKAY%s", message); }
''' + windows + "\n" + resource_defs + r'''
static ofnode ofnode_root(void) { return 0; }
static bool ofnode_valid(ofnode n) { return n >= 0; }
static ofnode ofnode_path(const char *path)
{
    unsigned int i;
    if (!strcmp(path, BIAS_BUS)) return bus_exists ? 9 : -1;
    if (!strcmp(path, LDH_CONFIG_NODE)) return config_exists ? 10 : -1;
    for (i = 0; i < 8; i++)
        if (!strcmp(path, windows[i].path)) return nodes & BIT(i) ? (int)i + 1 : -1;
    assert(0); return -1;
}
static int ofnode_device_is_compatible(ofnode n, const char *s)
{
    unsigned int i;
    if (n == 10) return config_compatible && !strcmp(s, LDH_CONFIG_COMPATIBLE);
    assert(!n);
    for (i = 0; i < 3; i++) if (!strcmp(compatible[i], s)) return 1;
    return 0;
}
static int ofnode_read_string_index(ofnode n, const char *prop, unsigned int i, const char **s)
{
    assert(!n && !strcmp(prop, "compatible") && i < 3);
    *s = compatible[i]; return 0;
}
static fdt_addr_t ofnode_get_addr_size_index(ofnode n, int index, fdt_size_t *size)
{
    assert(n > 0 && n <= 8 && !index);
    *size = sizes[n - 1]; return addresses[n - 1];
}
static bool ofnode_is_enabled(ofnode n)
{
    if (n == 10) return config_enabled;
    assert(n == 9); return bus_enabled;
}
static int uclass_get_device_by_ofnode(int id, ofnode n, struct udevice **dev)
{
    assert(id == UCLASS_I2C && n == 9);
    bus_calls++; *dev = &bus_device; return bus_error;
}
static int i2c_get_chip(struct udevice *bus, unsigned int addr, unsigned int offset, struct udevice **dev)
{
    assert(bus == &bus_device && addr == 0x11 && offset == 1);
    chip_calls++;
    if (!chip_error) *dev = &chip_device;
    return chip_error;
}
static int env_set(const char *key, const char *value)
{
    unsigned int n;
    if (!strcmp(key, "fastboot.display-count")) { assert(!value); row_count = 0; return 0; }
    assert(sscanf(key, "fastboot.display%u", &n) == 1 && n < 32);
    assert(strlen(value) < sizeof(rows[n]));
    strcpy(rows[n], value); return 0;
}
static int env_set_ulong(const char *key, unsigned long n)
{
    assert(!strcmp(key, "fastboot.display-count") && n <= 32);
    row_count = n; return 0;
}
''' + function(adapter, "terminal") + "\n" + function(adapter, "display_resources") + "\n" + function(adapter, "report_row") + "\n" + function(adapter, "display_report") + "\n" + function(adapter, "fastboot_oem_board") + r'''
static void setup(void)
{
    static const uint64_t base[] = {0x100000,0xaf00000,0xae00000,0xae01000,0xae94000,0xae96000,0xae94400,0xae96400};
    static const uint64_t size[] = {0x1f4200,0x20000,0x1000,0x8f000,0x400,0x400,0x200,0x200};
    memcpy(addresses, base, sizeof(base)); memcpy(sizes, size, sizeof(size));
    strcpy(compatible[0], "xiaomi,liuqin"); strcpy(compatible[1], "qcom,sm8475"); strcpy(compatible[2], "qcom,sm8450");
    nodes = 255; config_exists = config_enabled = config_compatible = bus_exists = bus_enabled = true;
    bus_calls = chip_calls = 0; bus_error = chip_error = 0; bias_chip = NULL;
    ldh_init(&handoff, NULL, NULL);
}
static void rejected(const char *step, int index)
{
    assert(display_resources() == -ENODEV && !strcmp(resource_info.step, step));
    assert(resource_info.error == -ENODEV && resource_info.bad_window == index);
    assert(!display_report() && row_count == 32);
    assert(!strcmp(rows[0], "v1 state=borrowed"));
}
int main(void)
{
    unsigned int i;
    char response[64];
    setup(); assert(!display_resources() && !strcmp(resource_info.step, "ready"));
    assert(bus_calls == 1 && chip_calls == 1 && resource_info.nodes == 255);
    assert(!display_resources() && bus_calls == 1 && chip_calls == 1); /* cached DM handle */
    assert(!display_report() && row_count == 32);
    /* Exact root list observed after ABL on the tablet. Root is metadata;
     * only the explicit liuqin contract can authorize the board sequence. */
    setup();
    strcpy(compatible[0], "qcom,cape-mtp"); strcpy(compatible[1], "qcom,cape"); strcpy(compatible[2], "qcom,mtp");
    assert(!display_resources() && resource_info.contract_match);
    assert(!resource_info.board_match && !resource_info.soc_match);
    assert(!display_report() && row_count == 32);
    assert(!strcmp(rows[18], "dt-match cfg=1 board=0 soc=0 nodes=ff"));
    config_exists = false; rejected("contract", -1); assert(bus_calls == 1); /* cached handle is no bypass */
    setup(); config_exists = false; rejected("contract", -1); assert(!bus_calls);
    setup(); config_enabled = false; rejected("contract", -1); assert(!bus_calls);
    setup(); config_compatible = false; rejected("contract", -1); assert(!bus_calls);
    setup();
    strcpy(compatible[0], "qcom,cape-mtp"); strcpy(compatible[1], "qcom,cape"); strcpy(compatible[2], "qcom,mtp");
    config_exists = false; rejected("contract", -1); assert(!bus_calls);
    for (i = 0; i < 8; i++) {
        setup(); nodes &= ~BIT(i); rejected("window", i); assert(!bus_calls);
        assert(resource_info.address[i] == FDT_ADDR_T_NONE);
        setup(); addresses[i] += 4; rejected("window", i); assert(!bus_calls);
        setup(); sizes[i]--; rejected("window", i); assert(!bus_calls);
    }
    setup(); bus_exists = false; rejected("i2c-node", -1); assert(!bus_calls);
    setup(); bus_enabled = false; rejected("i2c-node", -1); assert(!bus_calls);
    setup(); bus_error = -ENODEV; rejected("i2c-bus", -1); assert(!chip_calls);
    bus_error = 0; assert(!display_resources() && !resource_info.error); /* retry clears old diagnostic */
    setup(); chip_error = -ENODEV; rejected("i2c-chip", -1);
    setup(); memset(compatible[0], 'x', 79); compatible[0][79] = 0;
    assert(!display_resources() && !display_report() && row_count == 32);
    /* A later resource rejection must not mix in a previous raw error. */
    setup(); handoff.host = 1; handoff.fault_offset = 0xc; handoff.fault_value = BIT(10);
    config_exists = false;
    fastboot_oem_board("display-prepare", NULL, 0, response);
    assert(!strncmp(response, "FAIL", 4) && handoff.error == -ENODEV);
    assert(!handoff.host && !handoff.fault_offset && !handoff.fault_value);
    assert(!handoff.last_read.attempted);
    assert(!strcmp(rows[3], "raw-error@000=00000000"));
    /* A terminal failure instead keeps its evidence and never probes again. */
    setup(); handoff.state = LDH_FAILED; handoff.error = -EIO;
    handoff.host = 1; handoff.fault_offset = 0xc; handoff.fault_value = BIT(10);
    fastboot_oem_board("display-prepare", NULL, 0, response);
    assert(!strncmp(response, "FAIL", 4) && handoff.error == -EIO && !bus_calls);
    assert(handoff.host == 1 && handoff.fault_offset == 0xc && handoff.fault_value == BIT(10));
    puts("resources: Cape root with explicit board contract, all 8 windows, I2C errors, retry and bounded reports passed");
}
''', "test-resources", ["-I", str(board), str(board / "display-handoff.c")])
