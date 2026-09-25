// SPDX-License-Identifier: GPL-2.0+
/*
 * Xiaomi Pad 6 Pro (liuqin) USB2 path bring-up: NXP PTN3222 eUSB2 repeater.
 *
 * The SM8475 DWC3 (usb_1) USB2 data path goes through an eUSB2 HS PHY
 * (usb_1_hsphy) and then an NXP PTN3222 eUSB2-to-USB2 redriver that sits on
 * GENI I2C bus 5 (i2c5, SE qup1v2 SE5) at 7-bit address 0x4f. The repeater
 * powers up in reset (PMIC GPIO pm8350c_gpio7, active high) and needs a
 * short I2C parameter override sequence before USB2 works.
 *
 * Register sequence taken from the downstream Xiaomi kernel:
 *   drivers/usb/repeater/repeater-i2c-eusb2.c (NXP eUSB2 repeater, I2C
 *   writes of qcom,param-override-seq for peripheral mode) and the liuqin
 *   DT (qcom,param-override-seq = <0x40 0x06 0x00 0x07 0x63 0x08 0x03 0x0a>;
 *   reset-gpios = <&pm8350c_gpios 7 GPIO_ACTIVE_HIGH>). The format is
 *   { value, reg, ... } per pair as written by eusb2_repeater_update_seq().
 */

#include <dm.h>
#include <dm/pinctrl.h>
#include <dm/uclass.h>
#include <dm/ofnode.h>
#include <i2c.h>
#include <asm/gpio.h>
#include <linux/delay.h>

#include "liuqin.h"

void ptn3222_repeater_init(void);

#define PTN3222_I2C_ADDR	0x4f
#define PTN3222_REG_REVISION_ID	0x13

/* Upstream sm8450.dtsi puts the QUPv3 wrapper at /soc@0 and i2c5 is SE5. */
#define PTN3222_I2C_NODE	"/soc@0/geniqup@9c0000/i2c@994000"
#define PTN3222_NODE		PTN3222_I2C_NODE "/eusb2-repeater@4f"

/* { reg, value } pairs, peripheral (device) mode */
static const struct {
	u8 reg;
	u8 val;
} ptn3222_init_seq[] = {
	{ 0x06, 0x40 }, /* USB2_RX_CONTROL:  squelch/RX tuning  */
	{ 0x07, 0x00 }, /* USB2_TX_CONTROL1: TX amplitude default */
	{ 0x08, 0x63 }, /* USB2_TX_CONTROL2: pre-emphasis         */
	{ 0x0a, 0x03 }, /* USB2_HS termination / VDX tuning       */
};

static int ptn3222_i2c_write_seq(struct udevice *chip)
{
	int i, ret;

	for (i = 0; i < ARRAY_SIZE(ptn3222_init_seq); i++) {
		ret = dm_i2c_write(chip, ptn3222_init_seq[i].reg,
				   &ptn3222_init_seq[i].val, 1);
		if (ret) {
			printf("PTN3222: write reg 0x%02x failed: %d\n",
			       ptn3222_init_seq[i].reg, ret);
			return ret;
		}
	}

	return 0;
}

void ptn3222_repeater_init(void)
{
	struct gpio_desc reset;
	struct udevice *bus, *chip;
	ofnode bus_node, node;
	u8 rev = 0;
	int ret;

	/*
	 * Power the repeater from its RPMh rails first: without them the
	 * chip never ACKs on I2C. Values come from the stock/community DT
	 * (vdd18 = pm8350_s10 @ 1.8 V, vdd3 = pm8350_l2 @ 3.072 V).
	 */
	node = ofnode_path(PTN3222_NODE);
	liuqin_enable_supply(node, "vdd18-supply", 1800000);
	liuqin_enable_supply(node, "vdd3-supply", 3072000);
	mdelay(2);

	/*
	 * Take the repeater out of reset: pm8350c GPIO7, active high.
	 * The pmic-gpio driver is bound from the DTB; if that fails we
	 * still try the I2C writes so that USB works when the repeater
	 * was already released by a previous stage.
	 */
	ret = gpio_request_by_name_nodev(node, "reset-gpios", 0, &reset,
					 GPIOD_IS_OUT);
	if (!ret) {
		int r;

		r = dm_gpio_set_value(&reset, 0);	/* hold in reset */
		mdelay(5);
		r |= dm_gpio_set_value(&reset, 1);	/* release */
		mdelay(10);
		dm_gpio_free(reset.dev, &reset);
		printf("PTN3222: reset released (gpio set ret %d)\n", r);
	} else {
		printf("PTN3222: reset GPIO unavailable (%d), continuing\n", ret);
	}

	/*
	 * The i2c bus has no i2cN alias in this DTB, so its DM sequence
	 * number is not bus 5; find it by device tree node instead.
	 */
	bus_node = ofnode_path(PTN3222_I2C_NODE);
	if (!ofnode_valid(bus_node)) {
		printf("PTN3222: no I2C node %s\n", PTN3222_I2C_NODE);
		return;
	}
	ret = uclass_get_device_by_ofnode(UCLASS_I2C, bus_node, &bus);
	if (ret) {
		printf("PTN3222: I2C bus probe failed: %d\n", ret);
		return;
	}

	/*
	 * Probe may have run before the pad state could be resolved (pinctrl
	 * failures are non-fatal in device_probe), so re-apply it explicitly
	 * now that the full driver model exists.
	 */
	printf("PTN3222: i2c5 pinctrl ret=%d\n",
	       pinctrl_select_state(bus, "default"));

	ret = i2c_get_chip(bus, PTN3222_I2C_ADDR, 1, &chip);
	if (ret) {
		printf("PTN3222: no I2C chip at 0x%02x: %d\n",
		       PTN3222_I2C_ADDR, ret);
		return;
	}

	if (dm_i2c_read(chip, PTN3222_REG_REVISION_ID, &rev, 1))
		printf("PTN3222: no response at 0x%02x\n", PTN3222_I2C_ADDR);
	else
		printf("PTN3222: revision 0x%02x\n", rev);

	ret = ptn3222_i2c_write_seq(chip);
	if (ret)
		return;

	if (!dm_i2c_read(chip, PTN3222_REG_REVISION_ID, &rev, 1))
		printf("PTN3222: eUSB2 repeater initialised, rev 0x%02x\n", rev);
	else
		printf("PTN3222: init sequence written, rev read failed\n");
}
