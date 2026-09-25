// SPDX-License-Identifier: GPL-2.0+
/*
 * Xiaomi Pad 6 Pro (liuqin, SM8475) board init.
 *
 * What has to happen before anything else on this board can work:
 *
 *  - the Gunyah NS virtual watchdog ABL hands over with is relaxed and petted,
 *    because it is the only watchdog that lives outside the CPU and the whole
 *    storage bring-up below is one long window without a schedule() call;
 *  - console output starts being recorded at the first console line, since the
 *    panel and the ring in console.c are the only logs this board has;
 *  - the UFS controller/PHY rails and clocks come up before the bus is scanned
 *    (U-Boot's UFS and QMP PHY drivers ignore the DT's supplies and clocks);
 *  - the USB2 PHY is powered before the fastboot gadget probes it.
 *
 * The rest of the board support lives in the files listed at the top of
 * liuqin.h: video.c, console.c, gpt.c, qbootctl.c, slot.c, probe.c, power.c.
 */

#include <clk.h>
#include <command.h>
#include <console.h>
#include <cyclic.h>
#include <dm.h>
#include <dm/device-internal.h>
#include <dm/lists.h>
#include <dm/read.h>
#include <dm/root.h>
#include <dm/uclass.h>
#include <env.h>
#include <linux/arm-smccc.h>
#include <linux/kernel.h>
#include <linux/libfdt.h>
#include <power/pmic.h>
#include <power/regulator.h>
#include <scsi.h>
#include <stdio.h>
#include <video.h>
#include <asm/system.h>

#include "liuqin.h"

DECLARE_GLOBAL_DATA_PTR;

void ptn3222_repeater_init(void);
static void liuqin_diag_gunyah(void);
static void liuqin_usb_phy_enable(void);
static int liuqin_enable_reg_by_name(const char *name, int uv);
static void liuqin_vwdt_pet(void);

/*
 * Cross-reset boot stage log.
 *
 * The panel and the USB gadget are the only outputs this board has, and both
 * need working hardware to be seen: a build that dies before the framebuffer is
 * mapped, or before the gadget enumerates, leaves no evidence at all. Record the
 * stage in DRAM instead, at an address Linux never looks at, and read it back
 * through the next run - DRAM survives the reset:
 *
 *  - the scratch pad is the last page of the device tree's framebuffer
 *    carve-out (framebuffer@b8000000 + 0x2b00000): no-map for the kernel, so it
 *    is never mapped or written there, and the panel only scans the first
 *    20.7 MB of it. enable_caches() maps the whole carve-out, so the address
 *    stays writable once the MMU is on - the first markers run before that and
 *    go out physically;
 *  - the log keeps the previous run's lines, so a run that dies still reports
 *    its last stage through the next one (getvar stage, stage1, ...).
 */
#define LIUQIN_STAGE_ADDR	(0xb8000000UL + 0x2b00000UL - 0x1000)
#define LIUQIN_STAGE_MAGIC	0x5351494c	/* "LIQS" in memory (little-endian) */
#define LIUQIN_STAGE_LINES	24
#define LIUQIN_STAGE_LINE_LEN	44

struct liuqin_stage_log {
	u32 magic;
	u32 seq;
	u32 pad[2];
	char line[LIUQIN_STAGE_LINES][LIUQIN_STAGE_LINE_LEN];
};

/* It has to fit the page it lives in: past the carve-out is other memory. */
_Static_assert(sizeof(struct liuqin_stage_log) <= 0x1000,
	       "the stage log outgrew its page");

/* Also called from the mach board code, which carries a weak default. */
void liuqin_stage(const char *what)
{
	struct liuqin_stage_log *log = (void *)LIUQIN_STAGE_ADDR;
	u32 i;

	if (log->magic != LIUQIN_STAGE_MAGIC) {
		log->magic = LIUQIN_STAGE_MAGIC;
		log->seq = 0;
		for (i = 0; i < LIUQIN_STAGE_LINES; i++)
			log->line[i][0] = '\0';
	}

	log->seq++;
	for (i = 1; i < LIUQIN_STAGE_LINES; i++)
		memcpy(log->line[i - 1], log->line[i], LIUQIN_STAGE_LINE_LEN);
	snprintf(log->line[LIUQIN_STAGE_LINES - 1], LIUQIN_STAGE_LINE_LEN,
		 "%u: %s", (unsigned int)log->seq, what);
}

/*
 * Hand the recorded stages to the host, using the same protocol as
 * liuqin_console_capture(): fastboot.stagecount says how many to fetch,
 * fastboot.stage is the newest line and fastboot.stage1.. the older ones.
 *
 * The panel gets only the newest few lines: drawing each one costs real time
 * (the vidconsole software-renders into uncached DRAM), and this runs with the
 * Gunyah vWDT exactly as ABL armed it - the port no longer relaxes its 20 s
 * bark - so a long dump is a reset risk, not merely slow. The host channel
 * (getvar stage*, 16 entries) carries the older lines the panel drops.
 */
static void liuqin_stage_export(void)
{
	struct liuqin_stage_log *log = (void *)LIUQIN_STAGE_ADDR;
	char name[24];
	int i, n = 0;

	if (log->magic != LIUQIN_STAGE_MAGIC)
		return;

	liuqin_vwdt_pet();
	printf("stage log (%u entries):\n", (unsigned int)log->seq);
	for (i = LIUQIN_STAGE_LINES - 8; i < LIUQIN_STAGE_LINES; i++) {
		if (log->line[i][0])
			printf("  %s\n", log->line[i]);
	}
	liuqin_vwdt_pet();

	for (i = LIUQIN_STAGE_LINES - 1; i >= 0 && n < 16; i--) {
		if (!log->line[i][0])
			continue;
		if (n)
			snprintf(name, sizeof(name), "fastboot.stage%d", n);
		else
			snprintf(name, sizeof(name), "fastboot.stage");
		env_set(name, log->line[i]);
		n++;
	}
	env_set_ulong("fastboot.stagecount", n);
}

/* What the host reads back as `getvar build` to tell images apart. */
#define LIUQIN_DIAG_TAG		"v1"

/*
 * Gunyah NS virtual watchdog, driven over SMCCC (see the vendor kernel's
 * drivers/virt/gunyah/gh_virt_wdt.c). The community mainline DTB carries no
 * watchdog node and runs unattended, so the hypervisor most likely only arms it
 * once a guest enables it -- but ABL hands over with it armed and the vendor
 * kernel keeps it fed, and an armed vWDT resets any payload that stops petting
 * after the 20 s bark / 30 s bite. Cheap insurance: leave it enabled (disabling
 * it left hard-wedged boards recoverable only by power+volume-down) and pet it
 * from a cyclic callback while U-Boot runs. Its bark/bite times stay exactly as
 * ABL left them - U-Boot never relaxes them - which is what liuqin_vwdt and
 * getvar diag report.
 */
#define GH_VIRT_WDT_CONTROL	0x86000005
#define GH_VIRT_WDT_PET		0x86000007
#define GH_VIRT_WDT_SET_TIME	0x86000008
#define GH_VIRT_WDT_STATUS	0x86000006

static void liuqin_virt_wdt_smc(u32 id, u32 arg1, u32 arg2)
{
	struct arm_smccc_res res;

	arm_smccc_smc(id, arg1, arg2, 0, 0, 0, 0, 0, &res);
}

/*
 * Feed the Gunyah vWDT once. The watchdog is normally armed by the stage that
 * handed over with a 20 s bark (CONFIG_QCOM_WATCHDOG_BARK_TIME=20000), and the
 * hypervisor does not let us turn it off, so it is petted at every long-running
 * init step instead.
 */
static void liuqin_vwdt_pet(void)
{
	liuqin_virt_wdt_smc(GH_VIRT_WDT_PET, 0, 0);
}

/*
 * a1 bit0 is the control enable bit, a2 is the time since the last pet (the
 * vendor driver's gh_show_wdt_status(), drivers/virt/gunyah/gh_virt_wdt.c) and
 * a1 bit31 is the expired flag. Nothing in U-Boot changes the bark/bite times,
 * so what this reads is the state ABL handed over with.
 */
static void liuqin_vwdt_read(u32 *a1, u32 *a2)
{
	struct arm_smccc_res res;

	arm_smccc_smc(GH_VIRT_WDT_STATUS, 0, 0, 0, 0, 0, 0, 0, &res);
	*a1 = res.a1;
	*a2 = res.a2;
}

static struct cyclic_info liuqin_vwdt_cyclic;

static void liuqin_virt_wdt_pet(struct cyclic_info *c)
{
	liuqin_vwdt_pet();
}

/*
 * Called from board_init() in arch/arm/mach-snapdragon/board.c, which is early
 * in the post-relocation init sequence, before stdio init.
 */
void qcom_board_init(void)
{
	struct udevice *dev;
	int ret;

	liuqin_stage("qcom_board_init");
	liuqin_early_video_init();

	/*
	 * schedule() runs cyclic callbacks whenever U-Boot waits for input;
	 * petting every 10 s stays well inside the 20 s bark time even if the
	 * hypervisor refused the disable above.
	 */
	cyclic_register(&liuqin_vwdt_cyclic, liuqin_virt_wdt_pet,
			10 * 1000 * 1000, "gh-vwdt");

	/*
	 * Do NOT probe here: board_init() runs before stdio_init_tables(), and
	 * probing creates the vidconsole stdio device, whose registration would
	 * write into the still-uninitialised stdio list (Synchronous Abort). The
	 * console subsystem probes this device on demand when console_init_r()
	 * looks up "vidconsole" from stdout.
	 */
	ret = device_bind_driver(dm_root(), "liuqin_video", "liuqin_video", &dev);
	if (ret)
		printf("video bind failed: %d\n", ret);
	liuqin_stage("video bound");

	/*
	 * The device-model scan/probe that follows (UFS link training, USB, PHYs,
	 * regulators) can run for a long time without any schedule() call, so pet
	 * once here before that window opens.
	 */
	liuqin_vwdt_pet();
}

/*
 * The UFS controller and its PHY sit on rails the boot chain leaves off: VCC
 * (flash core, 2.5 V) and VCCQ/vdd-hba (1.2 V) for the controller, plus the
 * PHY's vdda-phy (0.88 V, shared with USB) and vdda-pll (1.2 V). Voltages follow
 * the stock bootloader DT.
 */
static void liuqin_ufs_supplies_enable(void)
{
	/*
	 * By name, not by ofnode: uclass_get_device_by_ofnode() fails with
	 * -ENODEV for these RPMh regulators (the same reason the USB bring-up
	 * reaches LDO10 by name). Names are "<resource><pmic-id>", so
	 * pm8350 -> ldob, pm8350c -> ldoc.
	 */
	liuqin_enable_reg_by_name("ldob7", 2504000);
	liuqin_enable_reg_by_name("ldob9", 1200000);
	liuqin_enable_reg_by_name("ldob5", 880000);
	liuqin_enable_reg_by_name("ldoc10", 1200000);
}

void qcom_board_late_init(void)
{
	static const char *const ufs_nodes[] = {
		"/soc@0/ufshc@1d84000",
		"/soc@0/phy@1d80000",
	};
	int i, j;

	liuqin_stage("qcom_board_late_init");
	env_set("fastboot.build", LIUQIN_DIAG_TAG);
	liuqin_diag_gunyah();
	liuqin_vwdt_pet();

	liuqin_usb_phy_enable();
	liuqin_vwdt_pet();
	ptn3222_repeater_init();
	liuqin_vwdt_pet();

	/*
	 * UFS bring-up: the QMP UFS PHY driver never touches its own clocks, so
	 * enable every clock the controller and the PHY list before the bus is
	 * scanned (the drivers themselves only handle the device rails).
	 */
	liuqin_ufs_supplies_enable();
	for (i = 0; i < ARRAY_SIZE(ufs_nodes); i++) {
		ofnode node = ofnode_path(ufs_nodes[i]);

		if (!ofnode_valid(node))
			continue;
		for (j = 0; ; j++) {
			struct clk clk;

			if (clk_get_by_index_nodev(node, j, &clk))
				break;
			clk_enable(&clk);
		}
	}
	liuqin_vwdt_pet();
	liuqin_stage("ufs supplies+clocks");

	/* Enumerate the LUNs and create the block devices fastboot needs. */
	if (scsi_scan(false))
		printf("ufs: scan failed; storage-backed boot paths may be unavailable\n");
	liuqin_vwdt_pet();
	liuqin_stage("ufs scanned");

	/*
	 * Hand the first console lines to the host through the fastboot getvar
	 * environment fallback (fastboot.con, fastboot.con1, ...): this board has
	 * no wired serial, so it is the only way to read the log without
	 * photographing the panel. Reading consumes the record
	 * (CONFIG_CONSOLE_RECORD), so this takes the first part and
	 * liuqin_conlog the rest on demand.
	 */
	liuqin_console_capture("con", 16);

	liuqin_stage("late init done");
	liuqin_vwdt_pet();
	liuqin_stage_export();
	printf("late init done\n");
}

/*
 * One-shot facts about the hand-off context, exported through fastboot getvar
 * so it can be read without photographing the panel:
 *   - U-Boot exception level,
 *   - whether the Gunyah vWDT SMC is answered (hypervisor present),
 *   - whether U-Boot's control FDT is the one ABL passed (model + /hypervisor).
 */
static void liuqin_diag_gunyah(void)
{
	u32 now[2] = {0, 0};
	const char *model;
	char buf[240];
	int hyp;

	liuqin_vwdt_read(&now[0], &now[1]);

	hyp = fdt_path_offset(gd->fdt_blob, "/hypervisor");
	model = fdt_getprop(gd->fdt_blob, 0, "model", NULL);
	snprintf(buf, sizeof(buf),
		 "el=%u hyp=%d fdt=%uK vwdt ctl%d age%u exp%d model=%s",
		 current_el(), hyp, fdt_totalsize(gd->fdt_blob) >> 10,
		 (int)(now[0] & 1), now[1], (int)((now[0] >> 31) & 1),
		 model ? model : "?");
	env_set("fastboot.diag", buf);
	printf("diag: %s\n", buf);
}

/*
 * liuqin_vwdt [<ms>] - report the Gunyah virtual watchdog, or set its bark and
 * bite time to <ms> and pet it.
 *
 * Nothing in mainline Linux pets this watchdog (the vendor's
 * drivers/virt/gunyah/gh_virt_wdt.c has no upstream equivalent), so a kernel
 * started from here inherits whatever U-Boot leaves behind.
 */
static int do_liuqin_vwdt(struct cmd_tbl *cmdtp, int flag, int argc,
			  char *const argv[])
{
	u32 st[2], ms;

	liuqin_vwdt_read(&st[0], &st[1]);
	printf("vwdt: ctl=%d age=%u expired=%d\n", (int)(st[0] & 1), st[1],
	       (int)((st[0] >> 31) & 1));

	if (argc < 2)
		return 0;

	ms = simple_strtoul(argv[1], NULL, 10);
	if (!ms) {
		printf("vwdt: refusing a zero timeout\n");
		return CMD_RET_USAGE;
	}
	liuqin_virt_wdt_smc(GH_VIRT_WDT_CONTROL, 3, 0);
	liuqin_virt_wdt_smc(GH_VIRT_WDT_SET_TIME, ms, ms);
	liuqin_vwdt_pet();
	liuqin_vwdt_read(&st[0], &st[1]);
	printf("vwdt: bark/bite %u ms -> ctl=%d age=%u\n", ms,
	       (int)(st[0] & 1), st[1]);

	return 0;
}

U_BOOT_CMD(liuqin_vwdt, 2, 0, do_liuqin_vwdt,
	"report or set the Gunyah virtual watchdog",
	"[<ms>] - without an argument, print ctl/age/expired from the hypervisor;\n"
	"  with one, set bark and bite to <ms> and pet the watchdog");

/*
 * Enable a regulator referenced by a supply property (shared with the PTN3222
 * bring-up). U-Boot's regulator uclass does not walk parent supplies, so every
 * rail a peripheral needs is enabled explicitly.
 */
int liuqin_enable_supply(ofnode node, const char *prop, int uv)
{
	struct udevice *reg;
	ofnode rnode;
	u32 phandle;
	int ret;

	ret = ofnode_read_u32(node, prop, &phandle);
	if (ret) {
		printf("liuqin: %s missing (%d)\n", prop, ret);
		return ret;
	}

	rnode = ofnode_get_by_phandle(phandle);
	ret = uclass_get_device_by_ofnode(UCLASS_REGULATOR, rnode, &reg);
	if (ret) {
		printf("liuqin: %s: no regulator (%d)\n", prop, ret);
		return ret;
	}

	ret = regulator_set_value(reg, uv);
	if (ret)
		printf("liuqin: %s: set %duV failed (%d)\n", prop, uv, ret);

	ret = regulator_set_enable(reg, true);
	if (ret)
		printf("liuqin: %s: enable failed (%d)\n", prop, ret);

	return ret;
}

static int liuqin_enable_reg_by_name(const char *name, int uv)
{
	struct udevice *reg;
	int ret;

	ret = uclass_get_device_by_name(UCLASS_REGULATOR, name, &reg);
	if (ret) {
		printf("liuqin: regulator %s not found (%d)\n", name, ret);
		return ret;
	}

	ret = regulator_set_value(reg, uv);
	if (ret)
		printf("liuqin: %s: set %duV failed (%d)\n", name, uv, ret);

	ret = regulator_set_enable(reg, true);
	printf("liuqin: %s %duV enable ret=%d\n", name, uv, ret);

	return ret;
}

/*
 * Power the USB2 HS PHY (usb_1_hsphy). Its U-Boot driver ignores the supplies
 * declared in the DT, so bring them up before the gadget path (fastboot or the
 * CDC-ACM console) probes the PHY. Rails follow the mainline liuqin DT: the
 * vdd/vdda12 (0.88 V / 1.2 V) pair powers the PHY, l2 the eUSB2 repeater.
 * Without the 1.2 V vdda12 rail the HS chirp works but the PHY never delivers
 * SETUP packets to the gadget (EP0 stalls).
 */
static void liuqin_usb_phy_enable(void)
{
	ofnode node = ofnode_path("/soc@0/phy@88e3000");

	if (!ofnode_valid(node)) {
		printf(LIUQIN_PREFIX "no usb_1_hsphy node\n");
		return;
	}

	liuqin_enable_supply(node, "vdda-pll-supply", 880000);
	liuqin_enable_reg_by_name("ldoc10", 1200000);
	liuqin_enable_supply(node, "vdda18-supply", 1800000);
	liuqin_enable_supply(node, "vdda33-supply", 3072000);
}
