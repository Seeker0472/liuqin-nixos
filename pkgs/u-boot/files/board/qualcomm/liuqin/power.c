// SPDX-License-Identifier: GPL-2.0+
/*
 * Reset, power-off and the two restart-reason cells.
 *
 * Next-boot mode lives in two places, exactly as the vendor msm-poweroff
 * restart handler writes them: the 32-bit magic in the IMEM restart_reason cell
 * (0x77665500 = bootloader, 0x77665502 = recovery) and the PON enum in the
 * PMK8350 SDAM cell the vendor DT names "restart_reason" (SDAM @0x7100, cell
 * @0x48, so SPMI register 0x7148 with the value in bits [7:1]).
 *
 * The restart cells are only half of the hand-off. The vendor kernel also
 * programs the PMK8350 PS_HOLD reset type and drops PS_HOLD through the
 * Qualcomm SCM service; a bare PSCI reset is not the same operation on this
 * board, and PSCI SYSTEM_OFF only resets it.
 */

#include <command.h>
#include <cpu_func.h>
#include <dm.h>
#include <dm/uclass.h>
#include <fastboot.h>
#include <linux/arm-smccc.h>
#include <linux/delay.h>
#include <linux/kernel.h>
#include <mapmem.h>
#include <power/pmic.h>
#include <asm/io.h>
#include <stdio.h>

#include "liuqin.h"

#define LIUQIN_IMEM_RESTART_REASON	0x146aa65cUL
#define LIUQIN_IMEM_MAGIC_BOOTLOADER	0x77665500
#define LIUQIN_IMEM_MAGIC_RECOVERY	0x77665502
#define LIUQIN_IMEM_MAGIC_NORMAL	0x77665501

#define LIUQIN_RESTART_REASON_REG	0x7148
#define LIUQIN_RESTART_REASON_NORMAL	0x20
#define LIUQIN_RESTART_REASON_BOOTLOADER	0x02
#define LIUQIN_RESTART_REASON_RECOVERY		0x01
#define LIUQIN_RESTART_REASON_FIELD		0xfe	/* bits [7:1] */

/*
 * qpnp_pon_system_pwr_off(PON_POWER_OFF_*): program the PMK8350 PON so that when
 * PS_HOLD drops, the PMIC does the requested thing instead of resetting. The
 * "pbs" register block is at 0x800 (pmk8350.dtsi reg-names = "hlos", "pbs"),
 * PS_HOLD_RST_CTL = pbs + 0x52 = 0x852 for PON GEN3.
 */
#define LIUQIN_PON_PS_HOLD_RST_CTL	0x852
#define LIUQIN_PON_PS_HOLD_RST_CTL2	0x853
#define LIUQIN_PON_RESET_EN		BIT(7)
#define LIUQIN_PON_POFF_TYPE_MASK	0x0f
/* Values from the vendor's own binding header,
 * include/dt-bindings/input/qcom,qpnp-power-on.h - the PMIC's DT does not
 * override them (no qcom,*-poweroff-type properties in the runtime DT), so the
 * driver programs exactly these. A plain reboot is
 * PON_POWER_OFF_TYPE_HARD_RESET ("Reset the MSM and all PMIC peripherals");
 * WARM_RESET deliberately leaves the PMIC peripherals - including the UFS
 * rails - untouched, and is only used by the vendor for dload/EDL/`reboot <cmd>`
 * (msm-poweroff.c:428-431). */
#define LIUQIN_PON_POFF_WARM_RESET	0x01	/* PON_POWER_OFF_TYPE_WARM_RESET */
#define LIUQIN_PON_POFF_SHUTDOWN	0x04	/* PON_POWER_OFF_TYPE_SHUTDOWN */
#define LIUQIN_PON_POFF_HARD_RESET	0x07	/* PON_POWER_OFF_TYPE_HARD_RESET */

/* Match qpnp_pon_reset_config(): disable PS_HOLD reset, wait ten sleep-clock
 * periods, program the type, then enable it and verify all three operations.
 * A best-effort write is not good enough for the Android hand-off: the type it
 * leaves behind is the difference between a reboot and a dark board. */
static int liuqin_pon_set_pshold_type(u8 type)
{
	ofnode node = ofnode_by_compatible(ofnode_null(), "qcom,pmk8350");
	struct udevice *pmic;
	int ctl, ctl2, ret;

	if (!ofnode_valid(node) ||
	    uclass_get_device_by_ofnode(UCLASS_PMIC, node, &pmic)) {
		printf("pon: no pmk8350 pmic device\n");
		return -ENODEV;
	}
	ctl = pmic_reg_read(pmic, LIUQIN_PON_PS_HOLD_RST_CTL);
	ctl2 = pmic_reg_read(pmic, LIUQIN_PON_PS_HOLD_RST_CTL2);
	printf("pon: rst_ctl=%#x rst_ctl2=%#x\n", ctl, ctl2);
	if (ctl < 0 || ctl2 < 0)
		return -EIO;

	ret = pmic_reg_write(pmic, LIUQIN_PON_PS_HOLD_RST_CTL2,
			     ctl2 & ~LIUQIN_PON_RESET_EN);
	if (ret)
		return ret;
	udelay(500);
	ret = pmic_reg_write(pmic, LIUQIN_PON_PS_HOLD_RST_CTL,
			     (ctl & ~LIUQIN_PON_POFF_TYPE_MASK) | type);
	if (ret)
		return ret;
	ret = pmic_reg_write(pmic, LIUQIN_PON_PS_HOLD_RST_CTL2,
			     (ctl2 & ~LIUQIN_PON_RESET_EN) | LIUQIN_PON_RESET_EN);
	if (ret)
		return ret;

	ctl = pmic_reg_read(pmic, LIUQIN_PON_PS_HOLD_RST_CTL);
	ctl2 = pmic_reg_read(pmic, LIUQIN_PON_PS_HOLD_RST_CTL2);
	printf("pon: pshold type=%#x -> rst_ctl=%#x rst_ctl2=%#x\n",
	       type, ctl, ctl2);
	if (ctl < 0 || ctl2 < 0 ||
	    (ctl & LIUQIN_PON_POFF_TYPE_MASK) != type ||
	    !(ctl2 & LIUQIN_PON_RESET_EN))
		return -EIO;

	return 0;
}

static int liuqin_pon_set_shutdown(void)
{
	return liuqin_pon_set_pshold_type(LIUQIN_PON_POFF_SHUTDOWN);
}

/*
 * QCOM_SCM_PWR_IO_DEASSERT_PS_HOLD (svc 0x09, cmd 0x02, owner SIP): the SoC
 * releases PS_HOLD and the PMIC acts. The encoding follows the kernel's
 * qcom_scm-smc.c: CALL_VAL(fast, SMC64/32, SIP, FNID(svc,cmd)), x1 =
 * arginfo = QCOM_SCM_ARGS(1) = 1, x2 = 0. The vendor driver notes this "should
 * never return if the SCM call is available".
 *
 * U-Boot is entered at a different EL depending on the ABL path, so both
 * conduits are tried and a return is reported to the caller as "use the generic
 * PSCI reset instead".
 */
static const struct {
	const char *name;
	bool hvc;
	u32 id;
} liuqin_pshold_calls[] = {
	{ "smc64", false, 0xc2000902 },
	{ "smc32", false, 0x82000902 },
	{ "hvc64", true,  0xc2000902 },
	{ "hvc32", true,  0x82000902 },
};

static int liuqin_deassert_ps_hold(const char *op)
{
	struct arm_smccc_res res;
	uint i;

	for (i = 0; i < ARRAY_SIZE(liuqin_pshold_calls); i++) {
		memset(&res, 0, sizeof(res));
		printf("%s: PS_HOLD deassert %s %#x ...\n", op,
		       liuqin_pshold_calls[i].name, liuqin_pshold_calls[i].id);
		if (liuqin_pshold_calls[i].hvc)
			arm_smccc_hvc(liuqin_pshold_calls[i].id, 1, 0, 0, 0, 0,
				      0, 0, &res);
		else
			arm_smccc_smc(liuqin_pshold_calls[i].id, 1, 0, 0, 0, 0,
				      0, 0, &res);
		printf("%s:   returned 0x%lx\n", op, res.a0);
	}

	printf("%s: no SCM conduit cut PS_HOLD\n", op);

	return -EIO;
}

static int do_liuqin_poweroff(struct cmd_tbl *cmdtp, int flag, int argc,
			      char *const argv[])
{
	liuqin_pon_set_shutdown();

	/* Give the PMIC a moment to latch the configuration. */
	mdelay(500);

	return liuqin_deassert_ps_hold("poweroff") ? CMD_RET_FAILURE :
						     CMD_RET_SUCCESS;
}

U_BOOT_CMD(poweroff, 1, 0, do_liuqin_poweroff,
	"power off the device",
	"- configure the PMIC for shutdown and deassert PS_HOLD via SCM");

static int liuqin_restart_reason_rw(bool write, u8 *value)
{
	ofnode node = ofnode_by_compatible(ofnode_null(), "qcom,pmk8350");
	struct udevice *pmic;
	int val, ret;

	if (!ofnode_valid(node))
		return -ENODEV;

	ret = uclass_get_device_by_ofnode(UCLASS_PMIC, node, &pmic);
	if (ret)
		return ret;

	val = pmic_reg_read(pmic, LIUQIN_RESTART_REASON_REG);
	if (val < 0)
		return val;

	if (!write) {
		*value = (val & LIUQIN_RESTART_REASON_FIELD) >> 1;
		return 0;
	}

	val = (val & ~LIUQIN_RESTART_REASON_FIELD) |
	      ((*value << 1) & LIUQIN_RESTART_REASON_FIELD);

	return pmic_reg_write(pmic, LIUQIN_RESTART_REASON_REG, val);
}

/* Write both cells for the next boot, then read them back and report what the
 * next boot will act on. A write that did not take must fail closed: a caller
 * that resets anyway boots the same slot again, while the operator believes the
 * other mode was requested. */
static int liuqin_restart_reason_set(u8 pon_value, u32 imem_magic, const char *op)
{
	void __iomem *imem;
	u32 magic_read;
	u8 pon_read = 0xff;
	int ret;

	/* PON cell first, IMEM magic last: a failure in between must not leave
	 * the magic saying "bootloader" while the PON cell still says normal. */
	ret = liuqin_restart_reason_rw(true, &pon_value);
	if (ret) {
		printf(LIUQIN_PREFIX "%s: PON write failed (%d)\n", op, ret);
		return ret;
	}

	imem = map_physmem(LIUQIN_IMEM_RESTART_REASON, sizeof(u32), MAP_NOCACHE);
	writel(imem_magic, imem);
	flush_dcache_range((ulong)imem, (ulong)imem + sizeof(u32));
	magic_read = readl(imem);
	unmap_physmem(imem, MAP_NOCACHE);

	ret = liuqin_restart_reason_rw(false, &pon_read);
	if (ret || magic_read != imem_magic || pon_read != pon_value) {
		printf(LIUQIN_PREFIX
		       "%s NOT set: imem=%#x (want %#x) pon=%#x (want %#x)\n",
		       op, magic_read, imem_magic, pon_read, pon_value);
		return ret ? ret : -EIO;
	}

	printf(LIUQIN_PREFIX "%s set: imem=%#x pon=%#x\n", op, magic_read,
	       pon_read);

	return 0;
}

/*
 * A U-Boot image reached through `fastboot boot` inherits the restart reason
 * that made ABL enter fastboot. If we merely call the generic reset command,
 * ABL sees that stale bootloader reason again and returns to fastboot instead
 * of loading the slot we just selected. The vendor kernel's normal reboot path
 * uses PON reason 0x20 and the matching IMEM "other/normal" magic; clear both
 * sides before handing Android back to ABL.
 */
static int liuqin_set_normal_reboot_reason(void)
{
	int ret;

	/* msm_restart_prepare() programs the PS_HOLD power-off type for the reset
	 * it is about to take: HARD_RESET for a plain reboot, WARM_RESET only
	 * when memory contents must survive (dload/EDL/"reboot <cmd>"), SHUTDOWN
	 * for power off (msm-poweroff.c:428-431, 517). Merely changing the reason
	 * cells and then issuing PSCI leaves this PMIC state unspecified, which
	 * is the difference between the vendor reboot and the old U-Boot path.
	 *
	 * HARD_RESET is also the only correct choice for the hand-off's other
	 * half: it resets the PMIC *peripherals*, so the UFS rails cycle and the
	 * bBootLunEn written a moment ago is what PBL reads. WARM_RESET leaves
	 * them powered, and a hand-off that armed it left the board dark and
	 * needed a manual power cycle (2026-09-24). */
	ret = liuqin_pon_set_pshold_type(LIUQIN_PON_POFF_HARD_RESET);
	if (ret) {
		printf(LIUQIN_PREFIX "normal restart: PON hard-reset setup failed (%d)\n",
		       ret);
		return ret;
	}

	return liuqin_restart_reason_set(LIUQIN_RESTART_REASON_NORMAL,
					 LIUQIN_IMEM_MAGIC_NORMAL,
					 "normal restart reason");
}

/*
 * Complete the vendor-style normal hand-off. The SCM call normally never
 * returns because PS_HOLD is physically released. Return a positive value only
 * when the reason pair was valid but the secure call returned; callers may then
 * use the generic PSCI reset as a last-resort fallback. A negative value means
 * the hand-off state itself was not safely prepared.
 */
int liuqin_normal_reboot(void)
{
	int ret;

	ret = liuqin_set_normal_reboot_reason();
	if (ret)
		return ret;
	if (liuqin_deassert_ps_hold("normal reboot")) {
		printf(LIUQIN_PREFIX
		       "normal reboot: SCM returned; PSCI fallback is required\n");
		return 1;
	}

	return 0;
}

int fastboot_set_reboot_flag(enum fastboot_reboot_reason reason)
{
	u8 pon_value;
	u32 magic;

	switch (reason) {
	case FASTBOOT_REBOOT_REASON_BOOTLOADER:
		magic = LIUQIN_IMEM_MAGIC_BOOTLOADER;
		pon_value = LIUQIN_RESTART_REASON_BOOTLOADER;
		break;
	case FASTBOOT_REBOOT_REASON_RECOVERY:
		magic = LIUQIN_IMEM_MAGIC_RECOVERY;
		pon_value = LIUQIN_RESTART_REASON_RECOVERY;
		break;
	default:
		return -EINVAL;
	}

	return liuqin_restart_reason_set(pon_value, magic, "restart reason");
}

static int do_ablfastboot(struct cmd_tbl *cmdtp, int flag, int argc,
			  char *const argv[])
{
	/*
	 * Write the very restart reason the fastboot protocol's
	 * "reboot-bootloader" writes (IMEM magic + PMK8350 SDAM PON), then
	 * reset: ABL comes up in fastboot instead of booting this slot again.
	 * A reason that did not take must not reset: a plain reset boots this
	 * slot again and reads as "the button did nothing".
	 */
	if (fastboot_set_reboot_flag(FASTBOOT_REBOOT_REASON_BOOTLOADER)) {
		printf("ablfastboot: restart reason not set; refusing to reset\n");
		return CMD_RET_FAILURE;
	}

	return do_reset(cmdtp, flag, argc, argv);
}

U_BOOT_CMD(ablfastboot, 1, 0, do_ablfastboot,
	"reboot into the stock ABL fastboot",
	"- write the bootloader restart reason and reset");
