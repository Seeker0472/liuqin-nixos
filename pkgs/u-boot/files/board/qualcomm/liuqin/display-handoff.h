/* SPDX-License-Identifier: GPL-2.0+ */
#ifndef LIUQIN_DISPLAY_HANDOFF_H
#define LIUQIN_DISPLAY_HANDOFF_H

#include <stdbool.h>

/* Board contract in the U-Boot control DT. Firmware may rewrite the root
 * compatible; neither a generic Cape root nor a register map identifies LCD.
 */
#define LDH_CONFIG_NODE "/display-handoff"
#define LDH_CONFIG_COMPATIBLE "xiaomi,liuqin-abl-display"

/* Fixed SM8475 register windows; offsets are relative to the raw DT reg. */
enum ldh_region {
	LDH_GCC, LDH_DISP_CC, LDH_MDSS, LDH_DPU,
	LDH_DSI0, LDH_DSI1, LDH_PHY0, LDH_PHY1,
};

enum ldh_state {
	LDH_BORROWED, LDH_PREPARED, LDH_COMMITTING, LDH_QUIESCED, LDH_FAILED,
};

enum ldh_stage {
	LDH_ACCESS, LDH_IDENTIFY, LDH_INTF, LDH_VIDEO, LDH_COMMAND,
	LDH_DISPLAY_OFF, LDH_SLEEP_IN, LDH_HOST, LDH_CLOCKS, LDH_PHY,
	LDH_BIAS, LDH_DONE,
};

/*
 * No allocation, DM, FDT, console or unbounded polling in the core. The same
 * code runs on the board and in the native fault-injection tests. MMIO writes
 * must be ordered (including against delay_us); reads must complete on return.
 * bias_* addresses the board's single KTZ8866, never an I2C address supplied
 * by a caller. freeze_console is one-way and must not fail.
 */
struct ldh_io {
	int (*read)(void *ctx, enum ldh_region region, unsigned int offset,
		    unsigned int *value);
	int (*write)(void *ctx, enum ldh_region region, unsigned int offset,
		     unsigned int value);
	int (*bias_read)(void *ctx, unsigned char reg, unsigned char *value);
	int (*bias_write)(void *ctx, unsigned char reg, unsigned char value);
	void (*delay_us)(void *ctx, unsigned int us);
	void (*freeze_console)(void *ctx);
};

enum ldh_error_reg {
	LDH_ERR_PHY, LDH_ERR_FIFO, LDH_ERR_ACK, LDH_ERR_TIMEOUT,
	LDH_ERR_CLOCK, LDH_ERR_STATUS, LDH_ERR_COUNT,
};

struct ldh_snapshot {
	unsigned int mdss_version, dpu_version, dsi_version[2];
	unsigned int ctrl[2], status[2], lanes[2], interrupts[2];
	unsigned int intf_enable[2], intf_status[2];
	unsigned int other_intf_status[2];
	unsigned int phy_ctrl[2], phy_pll[2];
	unsigned int raw_errors[2][LDH_ERR_COUNT];
	unsigned char bias_id, bias_config, backlight;
};

struct ldh {
	const struct ldh_io *io;
	void *ctx;
	enum ldh_state state;
	enum ldh_stage stage;
	int error;
	unsigned int host; /* Last host, for a failed stage. */
	unsigned int display_off_done, sleep_in_done;
	unsigned int link_gates_done; /* Each gate acknowledged off before PLL off. */
	unsigned int fault_offset, fault_value; /* First raw DSI error, if any. */
	struct {
		bool attempted;
		enum ldh_region region;
		unsigned int offset, value;
		int error;
	} last_read;
	struct ldh_snapshot before;
};

void ldh_init(struct ldh *handoff, const struct ldh_io *io, void *ctx);
/* Checks only: never writes a display/panel register or freezes the console. */
int ldh_prepare(struct ldh *handoff);
/* Revalidates even after prepare. QUIESCED is idempotent; FAILED is terminal. */
int ldh_commit(struct ldh *handoff);
const char *ldh_state_name(enum ldh_state state);
const char *ldh_stage_name(enum ldh_stage stage);

/* Transactional: only scratch changes. The caller publishes it after commit. */
int liuqin_display_fdt(const void *source, void *scratch, unsigned int capacity);

#endif
