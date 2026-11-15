/* SPDX-License-Identifier: GPL-2.0+ */
#ifndef BOOT_HANDOFF_H
#define BOOT_HANDOFF_H

struct bootm_headers;

/* Called by boot_selected_os on real Linux GO, after image/FDT preparation
 * and before arch/board preboot, USB, DM or CPU cleanup. On error a board may
 * return only if its console and
 * hardware are still usable; an irreversible failure must recover or halt.
 * FAKE_GO never calls this hook. The weak default does nothing. */
int board_linux_handoff(struct bootm_headers *images);

/* Called if a real Linux GO returns after cleanup. A board with an
 * irreversible handoff must not allow the caller to redraw its menu. */
void board_linux_handoff_returned(void);

/* USB fastboot is about to exit, with DM providers still alive. A board
 * helper may have irreversibly retired a device while USB remained usable. */
void board_fastboot_exit(void);

#endif
