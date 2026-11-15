// SPDX-License-Identifier: GPL-2.0+
/* Native execution of the production core against a small register model.
 * This proves ordering, failure semantics and bounded waits, not panel physics.
 */
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>

#include "display-handoff.h"

#define BIT(n) (1U << (n))
#define BASE(i) (0x35000U + (i) * 0x1000U)

struct cell { enum ldh_region r; unsigned int off, value; };
struct packet { unsigned int host, opcode, time; };
struct model {
	struct cell cells[128];
	unsigned int cells_used, calls, reads, writes, mdss_reads, mode_reads, fail_at;
	unsigned int time, frozen, gates, host_gated;
	unsigned int gate_off_at[8];
	unsigned int stopped_at[2], video_stopped_at[2], dma_at[2];
	unsigned int fifo[2][2], fifo_words[2], packet_count;
	struct packet packets[4];
	unsigned char bias[0x16];
	bool stuck_intf, stuck_video, stuck_dma, bad_ack, dma_error;
	bool bad_bias, gate_enable_stuck, delayed_gates;
	unsigned int stuck_gate; /* 1..8 selects one gate, zero means none. */
	bool masked_dma_error;
	bool video_needs_reset;
};

static unsigned int *reg(struct model *m, enum ldh_region r, unsigned int off)
{
	unsigned int i;

	for (i = 0; i < m->cells_used; i++)
		if (m->cells[i].r == r && m->cells[i].off == off)
			return &m->cells[i].value;
	assert(m->cells_used < 128);
	m->cells[m->cells_used] = (struct cell){ .r = r, .off = off };
	return &m->cells[m->cells_used++].value;
}

static bool fail(struct model *m)
{
	return ++m->calls == m->fail_at;
}

static void accessible(struct model *m, enum ldh_region r)
{
	if (r < LDH_MDSS)
		return;
	/* PHY APB uses the retained AHB/GDSC, not the pixel/byte/escape clocks.
	 * Host and DPU accesses have finished before the first link gate. */
	if (r < LDH_PHY0)
		assert(!m->gates);
	assert(*reg(m, LDH_GCC, 0x37004) & 1);
	assert(*reg(m, LDH_DISP_CC, 0x9000) & BIT(31));
	assert(*reg(m, LDH_DISP_CC, 0x80a4) & 1);
	if (r == LDH_DSI0 || r == LDH_DSI1)
		assert(!(m->host_gated & BIT(r - LDH_DSI0)));
}

static int model_read(void *ctx, enum ldh_region r, unsigned int off,
		      unsigned int *v)
{
	struct model *m = ctx;
	unsigned int i;

	accessible(m, r);
	m->reads++;
	if (r >= LDH_MDSS)
		m->mdss_reads++;
	if (r >= LDH_MDSS && !(off == 0 && r <= LDH_DSI1))
		m->mode_reads++;
	if (fail(m))
		return -EIO;
	for (i = 0; i < 2; i++) {
		if (!m->stuck_intf && m->stopped_at[i] &&
		    m->time >= m->stopped_at[i])
			*reg(m, LDH_DPU, BASE(i) + 0x26c) = 0;
		if (!m->stuck_video && !m->video_needs_reset && m->video_stopped_at[i] &&
		    m->time >= m->video_stopped_at[i])
			*reg(m, LDH_DSI0 + i, 8) &= ~BIT(3);
		if (!m->stuck_dma && m->dma_at[i] && m->time >= m->dma_at[i]) {
			*reg(m, LDH_DSI0 + i, 0x110) |= m->dma_error ? BIT(24) : BIT(0);
			*reg(m, LDH_DSI0 + i, 8) &= ~BIT(1);
			if (m->masked_dma_error)
				*reg(m, LDH_DSI0 + i, 0xc) |= BIT(10);
			m->dma_at[i] = 0;
		}
	}
	if (r == LDH_DISP_CC && m->delayed_gates) {
		static const unsigned int gate_regs[] = {
			0x8004, 0x8008, 0x802c, 0x8034,
			0x8028, 0x8030, 0x8038, 0x803c,
		};

		for (i = 0; i < 8; i++)
			if (m->gate_off_at[i] && m->time >= m->gate_off_at[i])
				*reg(m, LDH_DISP_CC, gate_regs[i]) |= BIT(31);
	}
	*v = *reg(m, r, off);
	return 0;
}

static void command(struct model *m, unsigned int id)
{
	unsigned int ctrl = *reg(m, LDH_DSI0 + id, 4);
	unsigned int dma = *reg(m, LDH_DSI0 + id, 0x3c);
	unsigned int word = m->fifo[id][0], op = word & 0xff;

	assert(m->fifo_words[id] == 2 && m->fifo[id][1] == 0);
	assert((word & ~0xffU) == 0x80050000U);
	assert((ctrl & 7) == 5); /* command only, host enabled */
	assert((dma & (BIT(31) | BIT(30) | BIT(28) | BIT(26))) == (BIT(28) | BIT(26)));
	assert((*reg(m, LDH_DSI0 + id, 0x84) & 7) == 4);
	assert(*reg(m, LDH_DSI0 + id, 0x4c) == 4);
	assert(*reg(m, LDH_DSI0 + id, 0x15c) == 0x30006);
	assert(m->packet_count < 4);
	assert(op == (m->packet_count < 2 ? 0x28 : 0x10));
	assert(id == (m->packet_count & 1));
	m->packets[m->packet_count++] = (struct packet){ id, op, m->time };
	m->dma_at[id] = m->time + 20;
	*reg(m, LDH_DSI0 + id, 8) |= BIT(1);
}

static int model_write(void *ctx, enum ldh_region r, unsigned int off,
		       unsigned int v)
{
	struct model *m = ctx;
	unsigned int id;

	assert(m->frozen == 1);
	accessible(m, r);
	m->writes++;
	if (fail(m))
		return -EIO;
	for (id = 0; id < 2; id++)
		if (r == LDH_DPU && off == BASE(id) && !v)
			m->stopped_at[id] = m->time + 1000;
	if (r == LDH_DSI0 || r == LDH_DSI1) {
		id = r - LDH_DSI0;
		if (off == 4 && !(v & BIT(1))) {
			/* Both interfaces finish BEFORE the first host is changed. */
			assert(!(*reg(m, LDH_DPU, BASE(0) + 0x26c) & 1));
			assert(!(*reg(m, LDH_DPU, BASE(1) + 0x26c) & 1));
			m->video_stopped_at[id] = m->time + 100;
		}
		if (off == 0x118 && v)
			*reg(m, r, 8) = m->stuck_video ? BIT(3) : 0;
		if (off == 0x110) {
			unsigned int old = *reg(m, r, off);

			/* Mixed W1C status and ordinary enable bits. */
			*reg(m, r, off) = (old & ~(m->bad_ack ? 0 : (v & BIT(0)))) |
					      (v & (BIT(1) | BIT(25)));
			return 0;
		}
		if (off == 0x1ec && v)
			m->fifo_words[id] = 0;
		if (off == 0x17c) {
			assert(m->fifo_words[id] < 2);
			m->fifo[id][m->fifo_words[id]++] = v;
		}
		if (off == 0x90 && v)
			command(m, id);
		if (off == 0x11c && !v) {
			assert(m->packet_count == 4);
			assert(m->time - m->packets[3].time >= 70000);
			assert(!(*reg(m, r, 4) & 7));
			m->host_gated |= BIT(id);
		}
	}
	if (r == LDH_PHY0 || r == LDH_PHY1) {
		assert(m->host_gated == 3);
		if (off == 0x24 && !v)
			assert(!*reg(m, r, 0x3c)); /* PLL off before PHY off */
	}
	if (r == LDH_DISP_CC) {
		bool source_on = *reg(m, LDH_PHY0, 0x3c) & BIT(0);

		assert(m->host_gated == 3);
		assert(!(v & 1));
		assert(m->gates < 8);
		m->gates++;
		/* Pixel and byte halt acknowledgement needs their live PHY PLL
		 * source. Do not invent an OFF transition after killing the source;
		 * that masked r4's dependency-order bug. Escape uses the XO. */
		if (m->stuck_gate != m->gates &&
		    (source_on || off == 0x8038 || off == 0x803c)) {
			if (m->delayed_gates)
				m->gate_off_at[m->gates - 1] = m->time + 100;
			else
				v |= BIT(31);
		}
		if (m->gate_enable_stuck)
			v |= BIT(0); /* A status-only predicate must not accept this. */
	}
	*reg(m, r, off) = v;
	return 0;
}

static int model_bias_read(void *ctx, unsigned char r, unsigned char *v)
{
	struct model *m = ctx;

	if (fail(m))
		return -EIO;
	*v = m->bias[r];
	return 0;
}

static int model_bias_write(void *ctx, unsigned char r, unsigned char v)
{
	struct model *m = ctx;

	assert(m->frozen == 1);
	assert(!*reg(m, LDH_PHY0, 0x24) && !*reg(m, LDH_PHY1, 0x24));
	m->writes++;
	if (fail(m))
		return -EIO;
	if (!m->bad_bias)
		m->bias[r] = v;
	return 0;
}

static void delay(void *ctx, unsigned int us)
{
	struct model *m = ctx;

	assert(us && us <= 70000);
	m->time += us;
	assert(m->time < 1000000); /* Every fault scenario must terminate. */
}

static void freeze(void *ctx)
{
	struct model *m = ctx;

	assert(!m->writes && !m->frozen);
	m->frozen++;
}

static const struct ldh_io io = {
	.read = model_read, .write = model_write,
	.bias_read = model_bias_read, .bias_write = model_bias_write,
	.delay_us = delay, .freeze_console = freeze,
};

static void setup(struct model *m, struct ldh *h)
{
	static const unsigned int clocks[] = {
		0x80a4, 0x800c, 0x8004, 0x8008, 0x8028, 0x802c, 0x8030, 0x8034,
		0x8038, 0x803c,
	};
	unsigned int i;

	memset(m, 0, sizeof(*m));
	*reg(m, LDH_GCC, 0x37004) = 1;
	*reg(m, LDH_DISP_CC, 0x9000) = BIT(31);
	for (i = 0; i < sizeof(clocks) / sizeof(clocks[0]); i++)
		*reg(m, LDH_DISP_CC, clocks[i]) = 1;
	m->video_needs_reset = true;
	*reg(m, LDH_MDSS, 0) = 0x80050000;
	*reg(m, LDH_DPU, 0) = 0x80050000;
	for (i = 0; i < 2; i++) {
		*reg(m, LDH_DSI0 + i, 0) = 0x20060001;
		*reg(m, LDH_DSI0 + i, 4) = 0x1f3;
		*reg(m, LDH_DSI0 + i, 8) = BIT(3);
		*reg(m, LDH_DSI0 + i, 0x110) = BIT(0); /* stale DMA_DONE */
		*reg(m, LDH_DSI0 + i, 0x11c) = 0x23f;
		*reg(m, LDH_DPU, BASE(i)) = 1;
		*reg(m, LDH_DPU, BASE(i) + 0x26c) = 1;
		*reg(m, LDH_PHY0 + i, 0x24) = 0x7f;
		*reg(m, LDH_PHY0 + i, 0x3c) = i ? 0 : 1; /* shared master PLL */
	}
	m->bias[1] = 0x21;
	m->bias[9] = 0x9f;
	m->bias[8] = 0x7f; /* DisplayDxe initialization, not Linux's later 0x5f */
	ldh_init(h, &io, m);
}

static unsigned int success(void)
{
	struct model m;
	struct ldh h;
	unsigned int calls;

	setup(&m, &h);
	assert(!ldh_prepare(&h) && h.state == LDH_PREPARED);
	assert(!m.writes && !m.frozen && !m.time);
	assert(!ldh_commit(&h));
	assert(h.state == LDH_QUIESCED && h.stage == LDH_DONE && !h.error);
	assert(h.display_off_done == 3 && h.sleep_in_done == 3);
	assert(h.link_gates_done == 0xff);
	assert(m.packet_count == 4 && m.gates == 8 && m.frozen == 1);
	assert(m.bias[9] == 0x98 && m.bias[8] == 0x3f);
	calls = m.calls;
	assert(!ldh_prepare(&h) && !ldh_commit(&h) && m.calls == calls);
	/* Get the number of operations for a fresh single commit. */
	setup(&m, &h);
	assert(!ldh_commit(&h));
	calls = m.calls;
	/* Also retain the configuration if the inherited Linux-style sink
	 * setting is present, or hardware stops video without needing reset. */
	setup(&m, &h);
	m.bias[8] = 0x5f;
	m.video_needs_reset = false;
	assert(!ldh_commit(&h) && m.bias[8] == 0x1f);
	setup(&m, &h);
	m.delayed_gates = true;
	assert(!ldh_commit(&h) && h.link_gates_done == 0xff);
	/* Owner's r4 prepare snapshot: nonzero raw status isn't necessarily
	 * an error, and host 0's extra STATUS bit13 must not block teardown. */
	setup(&m, &h);
	for (unsigned int i = 0; i < 2; i++) {
		*reg(&m, LDH_DSI0 + i, 0) = 0x20060000;
		*reg(&m, LDH_DSI0 + i, 4) = 0x1f7;
		*reg(&m, LDH_DSI0 + i, 8) = i ? 8 : 0x2008;
		*reg(&m, LDH_DSI0 + i, 0x110) = 0x10000;
		*reg(&m, LDH_DSI0 + i, 0xb4) = 0x88888;
		*reg(&m, LDH_DSI0 + i, 0xc) = 0x1210;
		*reg(&m, LDH_DSI0 + i, 0x120) = 0x8067c3;
	}
	assert(!ldh_commit(&h) && h.link_gates_done == 0xff);
	return calls;
}

static void rejects(void)
{
	struct model m;
	struct ldh h;
	unsigned int i;

	for (i = 0; i < 13; i++) {
		setup(&m, &h);
		switch (i) {
		case 0: *reg(&m, LDH_GCC, 0x37004) = 0; break;
		case 1: *reg(&m, LDH_DISP_CC, 0x9000) = 0; break;
		case 2: *reg(&m, LDH_DISP_CC, 0x80a4) = BIT(31); break;
		case 3: *reg(&m, LDH_DISP_CC, 0x8030) = BIT(31); break;
		case 4: *reg(&m, LDH_MDSS, 0) = 0x80000000; break;
		case 5: *reg(&m, LDH_DSI1, 0) = 0x20050000; break;
		case 6: *reg(&m, LDH_DSI1, 8) |= BIT(1); break;
		case 7: m.bias[1] = 0xff; break;
		case 8: m.bias[9] = 0x98; break;
		case 9: *reg(&m, LDH_DSI1, 0xc) = BIT(10); break;
		case 10: *reg(&m, LDH_MDSS, 0) = 0x80010000; break;
		case 11: *reg(&m, LDH_DPU, 0) = 0x80010000; break;
		case 12: *reg(&m, LDH_DPU, 0) = 0x90000000; break;
		}
		assert(ldh_commit(&h) < 0 && h.state == LDH_BORROWED);
		assert(!m.writes && !m.frozen);
		if (i < 4)
			assert(!m.mdss_reads);
		if (i == 4 || i == 5 || i >= 10) {
			assert(!m.mode_reads); /* IDs rejected before using a layout */
			assert(h.before.dsi_version[0] && h.before.dsi_version[1]);
		}
	}
	setup(&m, &h);
	assert(!ldh_prepare(&h));
	*reg(&m, LDH_DSI1, 0) = 0;
	assert(ldh_commit(&h) == -ENODEV && !m.writes && !m.frozen);
	/* A corrected non-destructive rejection is retryable. */
	*reg(&m, LDH_DSI1, 0) = 0x20060001;
	assert(!ldh_commit(&h));
	setup(&m, &h);
	*reg(&m, LDH_DSI1, 0xc) = BIT(10);
	assert(ldh_prepare(&h) == -EIO && h.fault_value == BIT(10));
	*reg(&m, LDH_DSI1, 0xc) = 0;
	assert(!ldh_prepare(&h) && !h.error && !h.fault_offset && !h.fault_value);
	assert(!m.frozen && !m.writes);
	setup(&m, &h);
	*reg(&m, LDH_DSI0, 0xc0) = 1;
	*reg(&m, LDH_DSI1, 0xc0) = 1;
	assert(ldh_prepare(&h) == -EIO && h.host == 0);
	assert(h.before.raw_errors[0][LDH_ERR_TIMEOUT] == 1);
	assert(h.before.raw_errors[1][LDH_ERR_TIMEOUT] == 1 && h.before.ctrl[1] == 0x1f3);
	assert(h.before.bias_id == 0x21 && h.before.bias_config == 0x9f);
	assert(!m.writes && !m.frozen); /* Full before snapshot, no latch clearing. */
}

static void faults(unsigned int operations)
{
	struct model m;
	struct ldh h;
	unsigned int i, calls;

	/* Fail EVERY actual backend operation along the successful path. */
	for (i = 1; i <= operations; i++) {
		setup(&m, &h);
		m.fail_at = i;
		assert(ldh_commit(&h) == -EIO);
		assert(m.calls == i && h.error == -EIO);
		if (h.last_read.error)
			assert(h.last_read.error == -EIO && h.last_read.value == 0);
		if (!m.frozen) {
			assert(h.state == LDH_BORROWED && !m.writes);
		} else {
			assert(h.state == LDH_FAILED);
			calls = m.calls;
			assert(ldh_prepare(&h) == -EPERM && ldh_commit(&h) == -EPERM);
			assert(h.error == -EIO && m.calls == calls);
		}
	}
	for (i = 0; i < 7; i++) {
		setup(&m, &h);
		switch (i) {
		case 0: m.stuck_intf = true; break;
		case 1: m.stuck_video = true; break;
		case 2: m.stuck_dma = true; break;
		case 3: m.bad_ack = true; break;
		case 4: m.dma_error = true; break;
		case 5: m.bad_bias = true; break;
		case 6: m.masked_dma_error = true; break;
		}
		assert(ldh_commit(&h) < 0 && h.state == LDH_FAILED);
		assert(h.error == (i < 3 ? -ETIMEDOUT : -EIO));
		if (i < 5)
			assert(!m.gates && m.bias[9] == 0x9f);
		if (i == 6)
			assert(h.fault_offset == 0xc && h.fault_value == BIT(10));
		if (i == 1)
			assert(h.stage == LDH_COMMAND); /* Failed to become idle AFTER reset. */
	}
	for (i = 0; i < 8; i++) {
		setup(&m, &h);
		m.stuck_gate = i + 1;
		assert(ldh_commit(&h) == -ETIMEDOUT && h.state == LDH_FAILED);
		assert(h.stage == LDH_CLOCKS && h.host == (i & 1));
		assert(h.link_gates_done == BIT(i) - 1);
		assert(m.gates == i + 1 && m.bias[9] == 0x9f);
		assert(*reg(&m, LDH_PHY0, 0x3c) == 1);
		assert(*reg(&m, LDH_PHY0, 0x24) == 0x7f);
		assert(*reg(&m, LDH_PHY1, 0x24) == 0x7f);
		calls = m.calls;
		assert(ldh_commit(&h) == -EPERM && m.calls == calls);
		assert(h.link_gates_done == BIT(i) - 1);
	}
	setup(&m, &h);
	m.gate_enable_stuck = true;
	assert(ldh_commit(&h) == -ETIMEDOUT && h.state == LDH_FAILED);
	assert(h.stage == LDH_CLOCKS && !h.link_gates_done);
	assert(m.gates == 1 && m.bias[9] == 0x9f);
}

int main(void)
{
	unsigned int operations = success();

	rejects();
	faults(operations);
	printf("display core: success, revalidation, %u injected I/O failures, 16 stuck/error cases passed\n", operations);
	return 0;
}
