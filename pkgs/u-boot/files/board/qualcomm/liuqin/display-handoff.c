// SPDX-License-Identifier: GPL-2.0+
/*
 * Borrow ABL scanout for the menu; stop it synchronously before Linux.
 *
 * Sequence evidence: dump DisplayDxe MDPStopPipe (RVA 0x1f8e4), DSITerm
 * (0x13814), host reset (0x15cec), PHY close (0x180a8), M81 off (0x106a4).
 * Register definitions: Linux dpu_hw_intf.c / dispcc-sm8450.c; Qualcomm's
 * dsi_ctrl_reg.h and dsi_ctrl_hw_cmn.c at e7ab2aa8bd2f. The latter's FIFO
 * command transport avoids borrowing ABL DMA buffers or SMMU mappings.
 * See docs/UBOOT-DISPLAY-HANDOFF.md for the deliberately retained resources.
 */

#include <errno.h>

#include "display-handoff.h"

#define BIT(n) (1U << (n))

/* Raw controller offsets, NOT the mainline 6G logical offsets (raw + 4). */
#define DSI_CTRL		0x004
#define DSI_STATUS		0x008
#define DSI_DMA_CTRL		0x03c
#define DSI_DMA_LENGTH		0x04c
#define DSI_TRIGGER_CTRL	0x084
#define DSI_DMA_TRIGGER		0x090
#define DSI_LANE_STATUS		0x0a8
#define DSI_HS_TIMER		0x0bc
#define DSI_INT_CTRL		0x110
#define DSI_SOFT_RESET		0x118
#define DSI_CLK_CTRL		0x11c
#define DSI_TPG_CTRL		0x15c
#define DSI_TPG_DATA		0x17c
#define DSI_TPG_RESET		0x1ec
#define DSI_CLK_FORCE_ON	(0x23fU | BIT(8) | BIT(9) | BIT(11) | BIT(21))
#define DSI_DMA_DONE		BIT(0)
#define DSI_ERROR		BIT(24)
#define DSI_POLL_INTERRUPTS	(BIT(1) | BIT(25))
#define PHY_CTRL		0x024
#define PHY_PLL			0x03c
#define INTF_BASE(id)		(0x35000U + (id) * 0x1000U)
#define INTF_STATUS		0x26c

#define WAIT_US			50000U
#define POLL_US			10U

_Static_assert(sizeof(unsigned int) == 4, "32-bit MMIO values required");

/* Only display link gates. AHB, MDP, GDSC, parent RCGs and votes stay owned
 * by firmware until Linux resets/adopts them. Never turn off USB/UFS rails. */
static const unsigned int link_gates[] = {
	0x8004, 0x8008, /* pclk0/1 */
	0x802c, 0x8034, /* byte0/1 interface */
	0x8028, 0x8030, /* byte0/1 */
	0x8038, 0x803c, /* esc0/1 */
};

static int rd(struct ldh *h, enum ldh_region r, unsigned int off,
	      unsigned int *v)
{
	int ret = h->io->read(h->ctx, r, off, v);

	h->last_read.attempted = true;
	h->last_read.region = r;
	h->last_read.offset = off;
	h->last_read.value = ret ? 0 : *v;
	h->last_read.error = ret;
	return ret;
}

static int wr(struct ldh *h, enum ldh_region r, unsigned int off,
	      unsigned int v)
{
	return h->io->write(h->ctx, r, off, v);
}

static int update(struct ldh *h, enum ldh_region r, unsigned int off,
		  unsigned int clear, unsigned int set)
{
	unsigned int v;
	int ret = rd(h, r, off, &v);

	return ret ? ret : wr(h, r, off, (v & ~clear) | set);
}

static int poll(struct ldh *h, enum ldh_region r, unsigned int off,
		unsigned int mask, unsigned int want)
{
	unsigned int elapsed, value;
	int ret;

	for (elapsed = 0; ; elapsed += POLL_US) {
		ret = rd(h, r, off, &value);
		if (ret || (value & mask) == want)
			return ret;
		if (elapsed == WAIT_US)
			return -ETIMEDOUT;
		h->io->delay_us(h->ctx, POLL_US);
	}
}

void ldh_init(struct ldh *h, const struct ldh_io *io, void *ctx)
{
	*h = (struct ldh){ .io = io, .ctx = ctx, .state = LDH_BORROWED };
}

static int access_check(struct ldh *h)
{
	unsigned int value, i;
	int ret;

	/* DISP_CC and GCC are outside the switched MDSS domain. Check access
	 * clocks and GDSC before the FIRST MDSS read, not after a bus fault. */
	ret = rd(h, LDH_GCC, 0x37004, &value); /* GCC_DISP_AHB_CLK */
	if (ret || !(value & BIT(0)) || (value & BIT(31)))
		return ret ? ret : -EHOSTDOWN;
	ret = rd(h, LDH_DISP_CC, 0x9000, &value); /* MDSS GDSCR */
	if (ret || !(value & BIT(31)))
		return ret ? ret : -EHOSTDOWN;
	ret = rd(h, LDH_DISP_CC, 0x80a4, &value); /* MDSS AHB */
	if (ret || !(value & BIT(0)) || (value & BIT(31)))
		return ret ? ret : -EHOSTDOWN;
	ret = rd(h, LDH_DISP_CC, 0x800c, &value); /* MDP */
	if (ret || !(value & BIT(0)) || (value & BIT(31)))
		return ret ? ret : -EHOSTDOWN;
	for (i = 0; i < sizeof(link_gates) / sizeof(link_gates[0]); i++) {
		ret = rd(h, LDH_DISP_CC, link_gates[i], &value);
		if (ret || !(value & BIT(0)) || (value & BIT(31)))
			return ret ? ret : -EHOSTDOWN;
	}
	return 0;
}

/* IRQ summary depends on inherited ERR_INT_MASK0. Inspect the raw latches
 * as well, using Qualcomm get_error_status()'s defined bits. Do not erase
 * inherited errors during prepare, or mistake masked errors for success. */
static const struct { unsigned int offset, mask; } error_regs[LDH_ERR_COUNT] = {
	{ 0x0b4, 0x11111 }, /* DLN0 PHY escape/control/contention */
	{ 0x00c, 0xcccc0480 }, /* command/lane FIFO over/underflow */
	{ 0x068, 0x01938000 }, /* ACK/ECC/CRC/peripheral errors */
	{ 0x0c0, 0x111 }, /* HS/LP/BTA timeouts */
	{ 0x120, BIT(16) }, /* PLL unlock */
	{ DSI_STATUS, BIT(31) }, /* interleave contention */
};

static int read_raw_errors(struct ldh *h, enum ldh_region dsi,
			   unsigned int values[LDH_ERR_COUNT])
{
	unsigned int i;
	int ret;

	for (i = 0; i < LDH_ERR_COUNT; i++) {
		ret = rd(h, dsi, error_regs[i].offset, &values[i]);
		if (ret)
			return ret;
	}
	return 0;
}

static int check_raw_errors(struct ldh *h, const unsigned int values[LDH_ERR_COUNT])
{
	unsigned int i;

	for (i = 0; i < LDH_ERR_COUNT; i++) {
		if (values[i] & error_regs[i].mask) {
			h->fault_offset = error_regs[i].offset;
			h->fault_value = values[i];
			return -EIO;
		}
	}
	return 0;
}

static int raw_errors(struct ldh *h, enum ldh_region dsi)
{
	unsigned int values[LDH_ERR_COUNT];
	int ret = read_raw_errors(h, dsi, values);

	return ret ? ret : check_raw_errors(h, values);
}

static int identify(struct ldh *h)
{
	struct ldh_snapshot *s = &h->before;
	unsigned int i;
	int ret;

#define READ(r, o, v) do { ret = rd(h, r, o, v); if (ret) return ret; } while (0)
	READ(LDH_MDSS, 0, &s->mdss_version);
	READ(LDH_DPU, 0, &s->dpu_version);
	/* Capture all independent ID registers before choosing a layout. The
	 * access clocks were checked above; no mode-specific registers yet. */
	for (i = 0; i < 2; i++)
		READ(LDH_DSI0 + i, 0, &s->dsi_version[i]);
	/* This SM8475 is 8.5 (also recorded by Linux before this port). It uses
	 * the sm8450 8.1 catalog layout; DisplayDxe 8.1/8.5 clock tables and HAL
	 * layouts match. A catalog filename is not the hardware revision. */
	if ((s->mdss_version >> 16) != 0x8005 ||
	    (s->dpu_version >> 16) != 0x8005)
		return -ENODEV;
	for (i = 0; i < 2; i++) {
		h->host = i;
		if ((s->dsi_version[i] & 0xffff0000) != 0x20060000)
			return -ENODEV; /* DisplayDxe's major 2 / minor 6 PHY backend */
	}
	/* Known layout: capture BOTH links and bias before judging state. A
	 * rejection on link 0 must not hide the safe readback from link 1. */
	READ(LDH_DPU, 0x34000 + INTF_STATUS, &s->other_intf_status[0]);
	READ(LDH_DPU, 0x37000 + INTF_STATUS, &s->other_intf_status[1]);
	for (i = 0; i < 2; i++) {
		enum ldh_region dsi = LDH_DSI0 + i;
		enum ldh_region phy = LDH_PHY0 + i;

		h->host = i;
		READ(dsi, DSI_CTRL, &s->ctrl[i]);
		READ(dsi, DSI_STATUS, &s->status[i]);
		READ(dsi, DSI_LANE_STATUS, &s->lanes[i]);
		READ(dsi, DSI_INT_CTRL, &s->interrupts[i]);
		READ(LDH_DPU, INTF_BASE(i), &s->intf_enable[i]);
		READ(LDH_DPU, INTF_BASE(i) + INTF_STATUS, &s->intf_status[i]);
		READ(phy, PHY_CTRL, &s->phy_ctrl[i]);
		READ(phy, PHY_PLL, &s->phy_pll[i]);
		ret = read_raw_errors(h, dsi, s->raw_errors[i]);
		if (ret)
			return ret;
	}
#undef READ
	ret = h->io->bias_read(h->ctx, 0x01, &s->bias_id);
	if (ret)
		return ret;
	ret = h->io->bias_read(h->ctx, 0x09, &s->bias_config);
	if (ret)
		return ret;
	ret = h->io->bias_read(h->ctx, 0x08, &s->backlight);
	if (ret)
		return ret;
	/* Do not stop a different firmware use of the display block. */
	if ((s->other_intf_status[0] | s->other_intf_status[1]) & BIT(0))
		return -EBUSY;
	for (i = 0; i < 2; i++) {
		h->host = i;
		ret = check_raw_errors(h, s->raw_errors[i]);
		if (ret)
			return ret;
		/* Active four-lane video splash, no in-flight command or error. */
		if ((s->ctrl[i] & 0x1f3) != 0x1f3 ||
		    (s->status[i] & 7) || (s->interrupts[i] & DSI_ERROR) ||
		    !(s->intf_enable[i] & 1) || !(s->intf_status[i] & 1) ||
		    !s->phy_ctrl[i] || (!i && !s->phy_pll[i]))
			return -EBUSY;
	}
	/* The observed KTZ8866 ID is 0x21; fail closed for another part. */
	if (s->bias_id != 0x21 || s->bias_config != 0x9f)
		return -ENODEV;
	return 0;
}

int ldh_prepare(struct ldh *h)
{
	int ret;

	if (h->state == LDH_QUIESCED)
		return 0;
	if (h->state == LDH_FAILED || h->state == LDH_COMMITTING)
		return -EPERM;
	h->state = LDH_BORROWED;
	h->before = (struct ldh_snapshot){0};
	h->host = 0;
	h->link_gates_done = 0;
	h->fault_offset = h->fault_value = 0;
	h->last_read.attempted = false;
	h->stage = LDH_ACCESS;
	ret = access_check(h);
	if (!ret) {
		h->stage = LDH_IDENTIFY;
		ret = identify(h);
	}
	h->error = ret;
	if (!ret)
		h->state = LDH_PREPARED;
	return ret;
}

/* Host off/reset with both internal and external access clocks available. */
static int host_reset(struct ldh *h, unsigned int id)
{
	enum ldh_region dsi = LDH_DSI0 + id;
	unsigned int clocks;
	int ret;

#define TRY(expr) do { ret = (expr); if (ret) return ret; } while (0)
	TRY(update(h, dsi, DSI_CTRL, 7, 0));
	TRY(rd(h, dsi, DSI_CLK_CTRL, &clocks));
	TRY(wr(h, dsi, DSI_CLK_CTRL, clocks | DSI_CLK_FORCE_ON));
	TRY(wr(h, dsi, DSI_SOFT_RESET, 1));
	h->io->delay_us(h->ctx, 1);
	TRY(wr(h, dsi, DSI_SOFT_RESET, 0));
	TRY(update(h, dsi, DSI_HS_TIMER, 0xfffff, 300000));
	TRY(wr(h, dsi, DSI_TPG_CTRL, 0));
	TRY(wr(h, dsi, DSI_TPG_RESET, 1));
	h->io->delay_us(h->ctx, 1);
	TRY(wr(h, dsi, DSI_TPG_RESET, 0));
	TRY(wr(h, dsi, DSI_CLK_CTRL, clocks));
	TRY(poll(h, dsi, DSI_SOFT_RESET, 1, 0));
	/* Stopping INTF can strand VIDEO_BUSY until this reset. Require an
	 * idle host AFTER reset, before issuing commands or gating clocks. */
	return poll(h, dsi, DSI_STATUS, 0x1f, 0);
}

static int dcs(struct ldh *h, unsigned int id, unsigned char opcode)
{
	enum ldh_region dsi = LDH_DSI0 + id;
	unsigned int elapsed, value;
	int ret;

	/* W1C stale DMA_DONE, enable the two polled interrupt sources. Never
	 * RMW a mixed mask/W1C register: a stale DONE must not complete this TX. */
	TRY(wr(h, dsi, DSI_INT_CTRL, DSI_DMA_DONE | DSI_POLL_INTERRUPTS));
	TRY(rd(h, dsi, DSI_INT_CTRL, &value));
	if (value & (DSI_DMA_DONE | DSI_ERROR))
		return -EIO;
	TRY(raw_errors(h, dsi));
	TRY(wr(h, dsi, DSI_TPG_CTRL, BIT(1) | BIT(2) | (3U << 16)));
	/* Embedded short DCS: last=1, VC=0, type=0x05, data0=opcode. The
	 * extra DWORD is hardware FIFO padding, not part of DMA_LENGTH. */
	TRY(wr(h, dsi, DSI_TPG_DATA, 0x80050000U | opcode));
	TRY(wr(h, dsi, DSI_TPG_DATA, 0));
	TRY(update(h, dsi, DSI_DMA_CTRL, BIT(31) | BIT(30), BIT(28) | BIT(26)));
	TRY(wr(h, dsi, DSI_DMA_LENGTH, 4));
	TRY(wr(h, dsi, DSI_DMA_TRIGGER, 1));
	for (elapsed = 0; ; elapsed += POLL_US) {
		TRY(rd(h, dsi, DSI_INT_CTRL, &value));
		if (value & DSI_ERROR)
			return -EIO;
		if (value & DSI_DMA_DONE)
			break;
		if (elapsed == WAIT_US)
			return -ETIMEDOUT;
		h->io->delay_us(h->ctx, POLL_US);
	}
	TRY(poll(h, dsi, DSI_STATUS, BIT(1), 0));
	TRY(raw_errors(h, dsi));
	TRY(wr(h, dsi, DSI_INT_CTRL, DSI_DMA_DONE)); /* ack, mask interrupts */
	TRY(wr(h, dsi, DSI_TPG_CTRL, 0));
	TRY(wr(h, dsi, DSI_TPG_RESET, 1));
	h->io->delay_us(h->ctx, 1);
	return wr(h, dsi, DSI_TPG_RESET, 0);
}

static int quiesce(struct ldh *h)
{
	unsigned int i, value;
	unsigned char byte;
	int ret;

	h->stage = LDH_INTF;
	for (i = 0; i < 2; i++) {
		h->host = i;
		TRY(wr(h, LDH_DPU, INTF_BASE(i), 0));
		/* Literal stop companion write in this dump's HAL (RVA 0x33744).
		 * Its name is not established; do not generalize to other DPUs. */
		TRY(wr(h, LDH_DPU, INTF_BASE(i) + 0x210, 1));
	}
	for (i = 0; i < 2; i++) {
		h->host = i;
		TRY(poll(h, LDH_DPU, INTF_BASE(i) + INTF_STATUS, 1, 0));
	}
	h->stage = LDH_VIDEO;
	for (i = 0; i < 2; i++) {
		h->host = i;
		TRY(update(h, LDH_DSI0 + i, DSI_CTRL, 6, 0));
	}
	for (i = 0; i < 2; i++) {
		h->host = i;
		/* No command DMA may be reset in flight. VIDEO_BUSY (bit3) and
		 * global DSI_BUSY (bit4) may persist until the host reset below.
		 * Mainline dsi_host.c and DisplayDxe both reset this condition. */
		TRY(poll(h, LDH_DSI0 + i, DSI_STATUS, 7, 0));
	}
	h->stage = LDH_COMMAND;
	for (i = 0; i < 2; i++) {
		h->host = i;
		TRY(host_reset(h, i));
		TRY(update(h, LDH_DSI0 + i, DSI_TRIGGER_CTRL, 7, 4));
		TRY(update(h, LDH_DSI0 + i, DSI_CTRL, 7, BIT(0) | BIT(2)));
	}
	h->stage = LDH_DISPLAY_OFF;
	for (i = 0; i < 2; i++) {
		h->host = i;
		TRY(dcs(h, i, 0x28));
		h->display_off_done |= BIT(i);
	}
	h->stage = LDH_SLEEP_IN;
	for (i = 0; i < 2; i++) {
		h->host = i;
		TRY(dcs(h, i, 0x10));
		h->sleep_in_done |= BIT(i);
	}
	h->io->delay_us(h->ctx, 70000); /* M81 TERM FF46, milliseconds */
	h->stage = LDH_HOST;
	for (i = 0; i < 2; i++) {
		h->host = i;
		TRY(host_reset(h, i));
		TRY(rd(h, LDH_DSI0 + i, DSI_CTRL, &value));
		if (value & 7)
			return -EIO;
		TRY(wr(h, LDH_DSI0 + i, DSI_INT_CTRL, DSI_DMA_DONE));
		/* Last host access. PHY APB uses the retained MDSS AHB clock. */
		TRY(wr(h, LDH_DSI0 + i, DSI_CLK_CTRL, 0));
	}
	h->stage = LDH_CLOCKS;
	/* Halt the consumers while their PHY PLL source still runs. Cutting
	 * that source first can strand CLOCK_OFF low even with enable=0.
	 * Host/DPU MMIO has ended; only PHY APB access follows, using the
	 * retained MDSS AHB/GDSC. No parent RCG or shared vote is changed. */
	for (i = 0; i < sizeof(link_gates) / sizeof(link_gates[0]); i++) {
		h->host = i & 1; /* Each adjacent pair is link 0, then link 1. */
		TRY(update(h, LDH_DISP_CC, link_gates[i], BIT(0), 0));
		TRY(poll(h, LDH_DISP_CC, link_gates[i], BIT(31) | BIT(0), BIT(31)));
		h->link_gates_done |= BIT(i);
	}
	h->stage = LDH_PHY;
	for (i = 0; i < 2; i++) {
		h->host = i;
		TRY(wr(h, LDH_PHY0 + i, PHY_PLL, 0));
		TRY(wr(h, LDH_PHY0 + i, PHY_CTRL, 0));
		TRY(poll(h, LDH_PHY0 + i, PHY_PLL, ~0U, 0));
		TRY(poll(h, LDH_PHY0 + i, PHY_CTRL, ~0U, 0));
	}
	h->stage = LDH_BIAS;
	/* Stop LED current while leaving HWEN and all shared PMIC rails alone. */
	TRY(h->io->bias_write(h->ctx, 0x08, h->before.backlight & ~BIT(6)));
	TRY(h->io->bias_write(h->ctx, 0x09, 0x98));
	TRY(h->io->bias_read(h->ctx, 0x09, &byte));
	if (byte != 0x98)
		return -EIO;
	TRY(h->io->bias_read(h->ctx, 0x08, &byte));
	if (byte & BIT(6))
		return -EIO;
	h->io->delay_us(h->ctx, 10000);
	return 0;
#undef TRY
}

int ldh_commit(struct ldh *h)
{
	int ret;

	ret = ldh_prepare(h);
	if (ret || h->state == LDH_QUIESCED)
		return ret;
	h->state = LDH_COMMITTING;
	h->io->freeze_console(h->ctx);
	ret = quiesce(h);
	h->error = ret;
	h->state = ret ? LDH_FAILED : LDH_QUIESCED;
	if (!ret)
		h->stage = LDH_DONE;
	return ret;
}

const char *ldh_state_name(enum ldh_state state)
{
	static const char *const names[] = {
		"borrowed", "prepared", "committing", "quiesced", "failed",
	};

	return names[state];
}

const char *ldh_stage_name(enum ldh_stage stage)
{
	static const char *const names[] = {
		"access", "identify", "intf", "video", "command", "display-off",
		"sleep-in", "host", "clocks", "phy", "bias", "done",
	};

	return names[stage];
}
