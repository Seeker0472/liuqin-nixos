// SPDX-License-Identifier: GPL-2.0+
/* U-Boot/DM adapter. All destructive display operations live in the core. */
#include <bootm.h>
#include <boot-handoff.h>
#include <dm.h>
#include <dm/uclass.h>
#include <env.h>
#include <fastboot.h>
#include <hang.h>
#include <i2c.h>
#include <malloc.h>
#include <sysreset.h>
#include <asm/io.h>
#include <linux/delay.h>
#include <linux/libfdt.h>

#include "liuqin.h"
#include "display-handoff.h"

#define MDSS_PATH "/soc@0/display-subsystem@ae00000"
#define BIAS_BUS "/soc@0/geniqup@9c0000/i2c@984000"

static struct ldh handoff;
static struct udevice *bias_chip;
static bool initialized;

static const struct {
	const char *path;
	phys_addr_t base;
	fdt_size_t size;
} windows[] = {
	[LDH_GCC] = { "/soc@0/clock-controller@100000", 0x100000, 0x1f4200 },
	[LDH_DISP_CC] = { "/soc@0/clock-controller@af00000", 0xaf00000, 0x20000 },
	[LDH_MDSS] = { MDSS_PATH, 0xae00000, 0x1000 },
	[LDH_DPU] = { MDSS_PATH "/display-controller@ae01000", 0xae01000, 0x8f000 },
	[LDH_DSI0] = { MDSS_PATH "/dsi@ae94000", 0xae94000, 0x400 },
	[LDH_DSI1] = { MDSS_PATH "/dsi@ae96000", 0xae96000, 0x400 },
	[LDH_PHY0] = { MDSS_PATH "/phy@ae94400", 0xae94400, 0x200 },
	[LDH_PHY1] = { MDSS_PATH "/phy@ae96400", 0xae96400, 0x200 },
};

/* Cache the metadata checks too: an ENODEV before the first MMIO must say
 * which contract failed, rather than looking like an all-zero register dump.
 */
static struct {
	const char *step;
	int error, bad_window;
	bool contract_match, board_match, soc_match;
	unsigned int nodes;
	fdt_addr_t address[ARRAY_SIZE(windows)];
	fdt_size_t size[ARRAY_SIZE(windows)];
	char compatible[3][44];
} resource_info = { .step = "not-run", .bad_window = -1 };

static const char *const window_names[] = {
	"gcc", "dispcc", "mdss", "mdp", "dsi0", "dsi1", "phy0", "phy1",
};

static int display_read(void *ctx, enum ldh_region region, unsigned int offset,
			unsigned int *value)
{
	if ((unsigned int)region >= ARRAY_SIZE(windows) || (offset & 3) ||
	    offset > windows[region].size - sizeof(u32))
		return -EINVAL;
	*value = readl((void __iomem *)(windows[region].base + offset));
	return 0;
}

static int display_write(void *ctx, enum ldh_region region, unsigned int offset,
			 unsigned int value)
{
	if ((unsigned int)region >= ARRAY_SIZE(windows) || (offset & 3) ||
	    offset > windows[region].size - sizeof(u32))
		return -EINVAL;
	writel(value, (void __iomem *)(windows[region].base + offset));
	/* Also order the write before a following delay, FIFO trigger or gate. */
	mb();
	return 0;
}

static int bias_read(void *ctx, unsigned char reg, unsigned char *value)
{
	return dm_i2c_read(bias_chip, reg, value, 1);
}

static int bias_write(void *ctx, unsigned char reg, unsigned char value)
{
	return dm_i2c_write(bias_chip, reg, &value, 1);
}

static void display_delay(void *ctx, unsigned int us)
{
	udelay(us);
}

static void display_freeze(void *ctx)
{
	liuqin_video_freeze();
}

static const struct ldh_io display_io = {
	.read = display_read,
	.write = display_write,
	.bias_read = bias_read,
	.bias_write = bias_write,
	.delay_us = display_delay,
	.freeze_console = display_freeze,
};

static void display_init(void)
{
	if (initialized)
		return;
	ldh_init(&handoff, &display_io, NULL);
	initialized = true;
}

static bool terminal(void)
{
	return handoff.state == LDH_QUIESCED || handoff.state == LDH_FAILED ||
	       handoff.state == LDH_COMMITTING;
}

static int display_resources(void)
{
	struct udevice *bus;
	ofnode bus_node, config;
	unsigned int i;
	int ret = 0;

	memset(&resource_info, 0, sizeof(resource_info));
	resource_info.step = "contract";
	resource_info.bad_window = -1;
	config = ofnode_path(LDH_CONFIG_NODE);
	resource_info.contract_match = ofnode_valid(config) &&
		ofnode_is_enabled(config) &&
		ofnode_device_is_compatible(config, LDH_CONFIG_COMPATIBLE);
	/* Root strings are diagnostics only. The ABL-facing tree arrives with
	 * qcom,cape-mtp/cape/mtp on this unit, despite a liuqin root in the image.
	 * Accept only the explicit board contract, then check all resources and
	 * hardware revisions. Do not identify the LCD by that generic root.
	 */
	resource_info.board_match = !!ofnode_device_is_compatible(ofnode_root(), "xiaomi,liuqin");
	resource_info.soc_match = !!ofnode_device_is_compatible(ofnode_root(), "qcom,sm8475");
	for (i = 0; i < ARRAY_SIZE(resource_info.compatible); i++) {
		const char *compatible;

		if (ofnode_read_string_index(ofnode_root(), "compatible", i, &compatible))
			break;
		snprintf(resource_info.compatible[i], sizeof(resource_info.compatible[i]),
			 "%.*s", (int)sizeof(resource_info.compatible[i]) - 1, compatible);
	}
	if (!resource_info.contract_match)
		ret = -ENODEV;
	/* Never probe MDSS drivers: these are inherited resources, not owned
	 * DM clock votes. Inspect ALL windows before any MMIO or provider probe,
	 * retaining the first failed check and the actual values for readback. */
	for (i = 0; i < ARRAY_SIZE(windows); i++) {
		ofnode node = ofnode_path(windows[i].path);

		resource_info.address[i] = FDT_ADDR_T_NONE;
		resource_info.size[i] = FDT_SIZE_T_NONE;
		if (ofnode_valid(node)) {
			resource_info.nodes |= BIT(i);
			resource_info.address[i] = ofnode_get_addr_size_index(node, 0,
							   &resource_info.size[i]);
		}
		if (!ret && (resource_info.address[i] != windows[i].base ||
			     resource_info.size[i] < windows[i].size)) {
			resource_info.step = "window";
			resource_info.bad_window = i;
			ret = -ENODEV;
		}
	}
	if (ret)
		goto done;
	if (bias_chip)
		goto ready;
	/* This initializes only I2C1 and its GPIO4/5 pads. In particular it
	 * never requests HWEN, panel reset, ENP/ENN or shared PMIC supplies. */
	resource_info.step = "i2c-node";
	bus_node = ofnode_path(BIAS_BUS);
	if (!ofnode_valid(bus_node) || !ofnode_is_enabled(bus_node)) {
		ret = -ENODEV;
		goto done;
	}
	resource_info.step = "i2c-bus";
	ret = uclass_get_device_by_ofnode(UCLASS_I2C, bus_node, &bus);
	if (ret)
		goto done;
	resource_info.step = "i2c-chip";
	ret = i2c_get_chip(bus, 0x11, 1, &bias_chip);
	if (ret)
		goto done;
ready:
	resource_info.step = "ready";
done:
	resource_info.error = ret;
	return ret;
}

/* Failed terminal shutdown cannot fall back to the invisible menu. Keep the
 * already-proven ABL recovery operation; if its reason write fails, halt. */
static void __noreturn display_recover(void)
{
	char message[64];

	snprintf(message, sizeof(message), "display %s %d h%u",
		 ldh_stage_name(handoff.stage), handoff.error, handoff.host);
	liuqin_stage(message);
	if (!fastboot_set_reboot_flag(FASTBOOT_REBOOT_REASON_BOOTLOADER))
		sysreset_walk_halt(SYSRESET_WARM);
	hang();
}

int board_linux_handoff(struct bootm_headers *images)
{
	void *scratch = NULL;
	unsigned int capacity;
	int ret;

	display_init();
	if (handoff.state == LDH_FAILED)
		display_recover();
	/* The generic loader has already validated/relocated kernel, initrd and
	 * FDT. Reject unsupported entry conventions before stopping scanout. */
	if (images->os.arch != IH_ARCH_ARM64 || !images->ep ||
	    !images->ft_addr || !images->ft_len || fdt_check_header(images->ft_addr)) {
		ret = -EINVAL;
		goto rejected;
	}
	/* image_setup_linux() leaves ft_len at the input size, but relocates and
	 * shrinks the final blob and recreates its LMB reservation. Only that
	 * blob's totalsize describes the buffer we may publish into. */
	capacity = fdt_totalsize(images->ft_addr);
	if (capacity < sizeof(struct fdt_header) || capacity > 0x400000) {
		ret = -EINVAL;
		goto rejected;
	}
	scratch = malloc(capacity);
	if (!scratch) {
		ret = -ENOMEM;
		goto rejected;
	}
	ret = liuqin_display_fdt(images->ft_addr, scratch, capacity);
	if (!ret && handoff.state != LDH_QUIESCED)
		ret = display_resources();
	if (!ret)
		ret = ldh_commit(&handoff);
	if (ret)
		goto rejected;
	/* Publication cannot fail and needs no driver after commit. The original
	 * LMB reservation, physical pointer and capacity remain unchanged. */
	memcpy(images->ft_addr, scratch, capacity);
	images->ft_len = capacity;
	free(scratch);
	liuqin_stage("display quiesced");
	return 0;

rejected:
	free(scratch);
	if (terminal())
		display_recover();
	printf(LIUQIN_PREFIX "display handoff rejected: %s (%d), host %u\n",
	       ldh_stage_name(handoff.stage), ret, handoff.host);
	return ret;
}

void board_linux_handoff_returned(void)
{
	/* A real kernel return is also terminal: generic cleanup has run. */
	display_recover();
}

void board_fastboot_exit(void)
{
	/* Explicit helper quiesce is one-way. USB stays up for readback until
	 * fastboot exits; continue, cable abort and local exit cannot redraw. */
	if (terminal())
		display_recover();
}

static int report_row(unsigned int row, const char *format, ...)
{
	char key[32], value[60];
	va_list args;
	int len;

	va_start(args, format);
	len = vsnprintf(value, sizeof(value), format, args);
	va_end(args);
	if (len < 0 || (size_t)len >= sizeof(value))
		return -E2BIG;
	snprintf(key, sizeof(key), "fastboot.display%u", row);
	return env_set(key, value);
}

static int display_report(void)
{
	const struct ldh_snapshot *s = &handoff.before;
	unsigned int i, row = 0;
	int ret;

	/* Count is the publication point; do not advertise a partial report. */
	ret = env_set("fastboot.display-count", NULL);
	if (ret)
		return ret;
#define ROW(...) do { ret = report_row(row++, __VA_ARGS__); if (ret) return ret; } while (0)
	ROW("v1 state=%s", ldh_state_name(handoff.state));
	ROW("stage=%s error=%d host=%u", ldh_stage_name(handoff.stage),
	    handoff.error, handoff.host);
	ROW("off-done=%x sleep-done=%x gates-done=%02x", handoff.display_off_done,
	    handoff.sleep_in_done, handoff.link_gates_done);
	ROW("raw-error@%03x=%08x", handoff.fault_offset, handoff.fault_value);
	ROW("mdss=%08x mdp=%08x", s->mdss_version, s->dpu_version);
	for (i = 0; i < 2; i++) {
		ROW("dsi%u ver=%08x ctrl=%08x", i, s->dsi_version[i], s->ctrl[i]);
		ROW("dsi%u status=%08x lanes=%08x tmo=%08x", i, s->status[i],
		    s->lanes[i], s->raw_errors[i][LDH_ERR_TIMEOUT]);
		ROW("dsi%u irq=%08x phyerr=%08x fifo=%08x", i, s->interrupts[i],
		    s->raw_errors[i][LDH_ERR_PHY], s->raw_errors[i][LDH_ERR_FIFO]);
		ROW("intf%u en=%08x status=%08x ack=%08x", i + 1, s->intf_enable[i],
		    s->intf_status[i], s->raw_errors[i][LDH_ERR_ACK]);
		ROW("phy%u ctrl=%08x pll=%08x clk=%08x", i, s->phy_ctrl[i],
		    s->phy_pll[i], s->raw_errors[i][LDH_ERR_CLOCK]);
	}
	ROW("ktz id=%02x bias=%02x bl=%02x", s->bias_id, s->bias_config, s->backlight);
	ROW("snapshot=before; MDP/AHB/GDSC/shared-rails retained");
	ROW("resources=%s error=%d bad=%d", resource_info.step,
	    resource_info.error, resource_info.bad_window);
	ROW("dt-match cfg=%u board=%u soc=%u nodes=%02x", resource_info.contract_match, resource_info.board_match,
	    resource_info.soc_match, resource_info.nodes);
	for (i = 0; i < ARRAY_SIZE(resource_info.compatible); i++)
		ROW("dt-compatible%u=%s", i, resource_info.compatible[i]);
	for (i = 0; i < ARRAY_SIZE(windows); i++)
		ROW("dt.%s=%llx/%llx", window_names[i],
		    (unsigned long long)resource_info.address[i],
		    (unsigned long long)resource_info.size[i]);
	ROW("other-intf=%08x/%08x", s->other_intf_status[0], s->other_intf_status[1]);
	if (handoff.last_read.attempted &&
	    (unsigned int)handoff.last_read.region < ARRAY_SIZE(windows))
		ROW("last-read %s+%x=%08x rc=%d", window_names[handoff.last_read.region],
		    handoff.last_read.offset, handoff.last_read.value, handoff.last_read.error);
	else
		ROW("last-read=none");
#undef ROW
	return env_set_ulong("fastboot.display-count", row);
}

void fastboot_oem_board(char *parameter, void *data, u32 size, char *response)
{
	int ret = 0, report;

	display_init();
	if (!parameter) {
		fastboot_fail("expected display-status/prepare/quiesce", response);
		return;
	}
	if (!strcmp(parameter, "display-prepare") ||
	    !strcmp(parameter, "display-quiesce")) {
		if (!terminal())
			ret = display_resources();
		if (!ret) {
			if (!strcmp(parameter, "display-prepare"))
				ret = ldh_prepare(&handoff);
			else
				ret = ldh_commit(&handoff);
		} else {
			ldh_init(&handoff, &display_io, NULL);
			handoff.error = ret;
		}
	} else if (strcmp(parameter, "display-status")) {
		fastboot_fail("unknown board operation", response);
		return;
	}
	/* status is cached and read-only: no MMIO after link gates are off. A
	 * failed manual commit deliberately leaves USB alive for this report. */
	report = display_report();
	if (ret || report)
		fastboot_fail(report ? "report export failed" : "display check/commit failed", response);
	else
		fastboot_okay(ldh_state_name(handoff.state), response);
}
