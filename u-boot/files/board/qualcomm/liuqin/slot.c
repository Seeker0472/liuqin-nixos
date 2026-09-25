// SPDX-License-Identifier: GPL-2.0+
/*
 * What a slot switch means.
 *
 * The A/B state is not in the misc partition: Qualcomm's ABL keeps it in the
 * GPT partition *attributes* of the boot_a/boot_b entries (bits 48-49 priority,
 * bit 50 active, bits 51-53 tries_remaining, bit 54 successful, bit 55
 * unbootable), which is also what the community port writes in
 * device/boot/liuqin-mark-slot-successful.c. A switch is two halves - the
 * attributes here and the identity layer in qbootctl.c - and the reset that
 * follows is what makes it irreversible, so everything is verified from media
 * before the caller is told it worked.
 *
 * The only persistent slot operation this image offers is the explicit Android
 * hand-off to A. There is deliberately no U-Boot successful marker: the
 * platform supplies no trustworthy proof that this execution came from
 * persistent boot_b rather than an ABL RAM boot, so that claim stays a human
 * menu action (docs/FACTS.md §2, §3.3).
 */

#include <android_image.h>
#include <command.h>
#include <cyclic.h>
#include <dm.h>
#include <dm/uclass.h>
#include <env.h>
#include <fastboot.h>
#include <linux/delay.h>
#include <linux/kernel.h>
#include <malloc.h>
#include <part.h>
#include <asm/byteorder.h>
#include <asm/system.h>
#include <stdio.h>

#include "liuqin.h"

static int liuqin_clear_bootonce_bcb(void);

/*
 * Check the minimum Android boot-image contract before handing a slot to ABL.
 * This is deliberately only the magic check: AVB/authentication belongs to
 * ABL, but pointing ABL at an empty or unrelated partition is a U-Boot error
 * that we can and should reject before changing GPT. Both the stock Android
 * boot image and our packaged U-Boot image start with ANDROID!.
 */
static int liuqin_slot_payload_ok(struct liuqin_gpt *g, const char *name)
{
	gpt_entry *ent = liuqin_gpt_find(g, name);
	u8 *block;
	u64 first;

	if (!ent) {
		liuqin_out_linef("slot: %s is missing", name);
		return -ENOENT;
	}
	first = le64_to_cpu(ent->starting_lba);
	if (!g->desc || !g->blksz ||
	    le64_to_cpu(ent->ending_lba) < first ||
	    le64_to_cpu(ent->ending_lba) > (u64)g->desc->lba) {
		liuqin_out_linef("slot: %s has invalid extent %llu..%llu", name,
				 (unsigned long long)first,
				 (unsigned long long)le64_to_cpu(ent->ending_lba));
		return -EINVAL;
	}

	block = memalign(g->blksz, g->blksz);
	if (!block) {
		liuqin_out_linef("slot: %s header buffer allocation failed", name);
		return -ENOMEM;
	}
	if (blk_dread(g->desc, first, 1, block) != 1) {
		liuqin_out_linef("slot: %s header read failed at %llu", name,
				 (unsigned long long)first);
		free(block);
		return -EIO;
	}
	if (memcmp(block, ANDR_BOOT_MAGIC, ANDR_BOOT_MAGIC_SIZE)) {
		liuqin_out_linef("slot: %s is not Android image (magic %02x%02x%02x%02x)",
				 name, block[0], block[1], block[2], block[3]);
		free(block);
		return -EBADMSG;
	}
	free(block);
	liuqin_out_linef("slot: %s Android magic verified", name);

	return 0;
}

/*
 * Qualcomm's set-active path is fail-closed: there must already be exactly one
 * active slot. A table with both bits clear or both bits set is not something
 * this image is allowed to guess about; use the stock ABL fastboot set_active
 * operation to establish the initial state, then return to U-Boot.
 */
static int liuqin_slot_active_guard(struct liuqin_gpt *g, const char *target,
				    const char *other)
{
	gpt_entry *target_ent = liuqin_gpt_find(g, target);
	gpt_entry *other_ent = liuqin_gpt_find(g, other);
	u64 target_attrs, other_attrs;

	if (!target_ent || !other_ent) {
		liuqin_out_linef("slot: active guard missing %s or %s", target,
				 other);
		return -ENOENT;
	}
	target_attrs = liuqin_ent_attrs(target_ent);
	other_attrs = liuqin_ent_attrs(other_ent);
	if (!!(target_attrs & LIUQIN_SLOT_ACTIVE) ==
	    !!(other_attrs & LIUQIN_SLOT_ACTIVE)) {
		if (!(target_attrs & LIUQIN_SLOT_ACTIVE) &&
		    !(other_attrs & LIUQIN_SLOT_ACTIVE)) {
			liuqin_out_linef("slot: no active slot (%s=0 %s=0)",
					 target, other);
			liuqin_out_linef("slot: next use ABL fastboot set_active a");
		} else {
			liuqin_out_linef("slot: both slots active (%s=1 %s=1)",
					 target, other);
			liuqin_out_linef("slot: normalize with ABL fastboot set_active a");
		}
		return -EINVAL;
	}

	return 0;
}

/*
 * Make @slot the slot ABL boots next. ABL picks the bootable slot with the
 * highest priority, so the selected slot gets its complete Qualcomm state byte
 * rather than a few merged bits: priority 3, active, seven tries, and neither
 * successful nor unbootable.
 *
 * @action decides whether the two halves that make a switch complete are part
 * of this call: the UFS boot LUN and the type-GUID roles belong to a slot
 * *selection*, while AOSP's markBootSuccessful writes the successful bit and
 * nothing else (docs/FACTS.md §3.3).
 *
 * Return: 0 on success (verified from disk), negative errno otherwise.
 */
int liuqin_ab_commit_slot(char slot, bool successful,
			  enum liuqin_slot_action action)
{
	struct liuqin_gpt pri = {0};
	struct blk_desc *desc;
	enum liuqin_gpt_commit_status st;
	char target[8], other[8];
	const char *why = NULL;
	bool quiet;
	gpt_entry *target_ent, *other_ent;
	u8 active_type[LIUQIN_AB_TYPE_GUID_COUNT][16] = { 0 };
	u8 inactive_type[LIUQIN_AB_TYPE_GUID_COUNT][16] = { 0 };
	char current_slot;
	u32 boot_lun_before = 0;
	u64 self, other_before, at = 0, other_at = 0;
	int ret;

	snprintf(target, sizeof(target), "boot_%c", slot);
	snprintf(other, sizeof(other), "boot_%c", slot == 'a' ? 'b' : 'a');

	/*
	 * Everything this command learns about the table goes into the ring and
	 * out through getvar (fastboot.gpt*, see liuqin_console_capture()): the
	 * panel is redrawn by the menu as soon as the command returns, so a
	 * refusal printed there is gone before it can be read. Only the verdict
	 * stays on the panel.
	 */
	quiet = liuqin_quiet;
	liuqin_quiet = true;

	desc = liuqin_gpt_holding(&pri, target);
	if (!desc) {
		liuqin_out_linef("slot: no GPT holds %s (primary CRC-valid)", target);
		ret = -ENOENT;
		goto out;
	}
	if (!liuqin_gpt_semantic_ok(&pri, &why)) {
		liuqin_out_linef("slot: semantic GPT check failed (%s)",
				 why ? why : "unknown");
		ret = -EINVAL;
		goto out;
	}
	ret = liuqin_slot_active_guard(&pri, target, other);
	if (ret)
		goto out;
	ret = liuqin_slot_payload_ok(&pri, target);
	if (ret)
		goto out;
	target_ent = liuqin_gpt_find(&pri, target);
	other_ent = liuqin_gpt_find(&pri, other);	/* the guard checked both */

	/* qbootctl opens the UFS boot-LUN control path before it changes GPT.
	 * Mirror that ordering: a missing Query Attribute channel must leave the
	 * table untouched rather than creating a slot/XBL mismatch. Only a slot
	 * *selection* does this - a mark must neither depend on the UFS attribute
	 * nor move the boot source. */
	if (action == LIUQIN_SLOT_SELECT) {
		ret = liuqin_boot_lun_prepare(slot, &boot_lun_before);
		if (ret)
			goto out;
	}

	self = liuqin_ent_attrs(target_ent);
	other_before = liuqin_ent_attrs(other_ent);
	liuqin_out_linef("slot: before %s %04llx %s %04llx", target,
			 (unsigned long long)(self >> 48), other,
			 (unsigned long long)(other_before >> 48));
	current_slot = (self & LIUQIN_SLOT_ACTIVE) ? slot :
		       (slot == 'a' ? 'b' : 'a');
	if (action == LIUQIN_SLOT_SELECT) {
		ret = liuqin_slot_type_guids_prepare(&pri, slot, current_slot,
						     active_type, inactive_type);
		if (ret)
			goto out;
	}

	/*
	 * Demote the other slot the way ABL's SetActiveSlot does: clear the
	 * active bit and (on a two-slot device) drop the priority to 2, leaving
	 * tries_remaining, successful and unbootable exactly as they are. ABL
	 * never touches those three, so overwriting the whole state byte here
	 * used to clear a human's "mark slot B successful" (docs/FACTS.md §2)
	 * and hand the fallback a fresh retry budget behind ABL's back.
	 */
	liuqin_ent_set_attrs(other_ent,
			     (other_before & ~(LIUQIN_SLOT_ACTIVE |
					       LIUQIN_SLOT_PRIO_MASK)) |
			     LIUQIN_SLOT_PRIO_2);
	liuqin_ent_set_attrs(target_ent,
			     (self & ~LIUQIN_SLOT_STATE_MASK) |
			     ((LIUQIN_SLOT_ACTIVE_VALUE |
			       (successful ? LIUQIN_SLOT_SUCCESSFUL_VALUE : 0))
			      << 48));

	st = liuqin_gpt_commit(&pri);
	if (st != LIUQIN_GPT_COMMIT_OK) {
		liuqin_out_linef("slot: GPT commit failed (%s)",
				 st == LIUQIN_GPT_COMMIT_PAIR_FAIL ?
				 "copies disagree" : "write did not stick");
		ret = -EIO;
		goto out;
	}

	/*
	 * Verify from disk. The commit proved that the two copies of the table
	 * agree with each other; what it cannot prove is that the bytes we built
	 * are the state we meant, and the reset this may end in is what makes a
	 * wrong answer irreversible.
	 */
	liuqin_gpt_free(&pri);
	if (!liuqin_gpt_holding(&pri, target)) {
		liuqin_out_linef("slot: %s unreadable after the write", target);
		goto verify_fail;
	}
	target_ent = liuqin_gpt_find(&pri, target);
	other_ent = liuqin_gpt_find(&pri, other);
	if (!target_ent || !other_ent) {
		liuqin_out_linef("slot: an entry vanished after the write");
		goto verify_fail;
	}
	at = liuqin_ent_attrs(target_ent);
	other_at = liuqin_ent_attrs(other_ent);
	if ((at & LIUQIN_SLOT_PRIO_MASK) != LIUQIN_SLOT_PRIO_MASK ||
	    (at & LIUQIN_SLOT_TRIES_MASK) != LIUQIN_SLOT_TRIES_MASK ||
	    !(at & LIUQIN_SLOT_ACTIVE) || (at & LIUQIN_SLOT_UNBOOTABLE) ||
	    !!(at & LIUQIN_SLOT_SUCCESSFUL) != successful)
		goto verify_fail;
	/*
	 * The demotion is "active cleared, priority 2" and nothing else: the
	 * other slot's retry budget, successful and unbootable claims have to
	 * come back bit-identical to what was on media before this ran.
	 */
	if ((other_at & (LIUQIN_SLOT_ACTIVE | LIUQIN_SLOT_PRIO_MASK)) !=
	    LIUQIN_SLOT_PRIO_2 ||
	    (other_at & ~(LIUQIN_SLOT_ACTIVE | LIUQIN_SLOT_PRIO_MASK)) !=
	    (other_before & ~(LIUQIN_SLOT_ACTIVE | LIUQIN_SLOT_PRIO_MASK)))
		goto verify_fail;
	if (action == LIUQIN_SLOT_SELECT) {
		if (liuqin_slot_type_guids_verify(&pri, slot, active_type,
						  inactive_type))
			goto verify_fail;

		/* GPT attributes and the UFS boot LUN are one hand-off: do not
		 * hand the reset to ABL until the second half has been written
		 * and read back. */
		ret = liuqin_boot_lun_commit(slot, boot_lun_before);
		if (ret)
			goto out;
	}

	/* The Android hand-off is also the point at which a stale ABL one-shot
	 * fastboot command must be consumed. Keep this out of the B-slot path:
	 * selecting or marking U-Boot must not touch misc. */
	if (slot == 'a' && liuqin_clear_bootonce_bcb()) {
		liuqin_out_linef("slot: Android hand-off BCB clear failed");
		ret = -EIO;
		goto out;
	}

	liuqin_out_linef("slot: %s is now %04llx, %s demoted to %04llx", target,
			 (unsigned long long)(at >> 48), other,
			 (unsigned long long)(other_at >> 48));
	ret = 0;
	goto out;

verify_fail:
	liuqin_out_linef("slot: switching to %s FAILED, attrs now %04llx", target,
			 (unsigned long long)(at >> 48));
	ret = -EIO;
out:
	liuqin_gpt_free(&pri);
	liuqin_console_capture("gpt", 8);
	liuqin_quiet = quiet;

	/* One panel line: the verdict, and where the reason can be read. */
	if (ret)
		printf("slot: %c failed - reason in fastboot.gpt*\n", slot);
	else
		printf("slot: %s active%s, pri+bak written\n", target,
		       successful ? " + successful" : "");

	return ret;
}

/*
 * ABL's fastboot entry path can leave a one-shot command in misc. It is not the
 * A/B slot store, but ABL does consult its first 32-byte command field when it
 * decides what to do after a reset: a stale "bootonce-bootloader" makes a
 * perfectly valid set_active+reset loop back into ABL fastboot.
 *
 * Do not zero misc wholesale: recovery/update metadata lives after this command
 * field. Find the real misc partition by GPT, require a complete block
 * read/write, and clear only the exact command we own. A command we do not
 * understand is reported and preserved; a read/write/flush/read-back failure is
 * fatal to the Android hand-off.
 */
#define LIUQIN_BCB_COMMAND_BYTES	32
#define LIUQIN_BCB_BOOTONCE		"bootonce-bootloader"

static void liuqin_bcb_command_text(const u8 *block, char *out, size_t size)
{
	size_t i;

	for (i = 0; i + 1 < size && i < LIUQIN_BCB_COMMAND_BYTES; i++) {
		u8 c = block[i];

		if (!c)
			break;
		out[i] = c >= 0x20 && c <= 0x7e ? c : '.';
	}
	out[i] = '\0';
}

static int liuqin_clear_bootonce_bcb(void)
{
	struct liuqin_gpt misc = {0};
	struct blk_desc *desc;
	gpt_entry *ent;
	u8 *block = NULL, *readback = NULL;
	char command[LIUQIN_BCB_COMMAND_BYTES + 1];
	u64 first, last;
	const size_t command_len = sizeof(LIUQIN_BCB_BOOTONCE) - 1;
	int ret = 0;

	desc = liuqin_gpt_holding(&misc, "misc");
	if (!desc) {
		liuqin_out_linef("misc: no CRC-valid GPT holds misc");
		ret = -ENOENT;
		goto out;
	}
	ent = liuqin_gpt_find(&misc, "misc");
	first = le64_to_cpu(ent->starting_lba);
	last = le64_to_cpu(ent->ending_lba);
	if (misc.blksz < LIUQIN_BCB_COMMAND_BYTES || first > last ||
	    last > (u64)desc->lba ||
	    !liuqin_gpt_range_ok(first, 1, (u64)desc->lba)) {
		liuqin_out_linef("misc: invalid extent %llu..%llu or block size %lu",
				 (unsigned long long)first, (unsigned long long)last,
				 misc.blksz);
		ret = -EINVAL;
		goto out;
	}

	block = memalign(misc.blksz, misc.blksz);
	readback = memalign(misc.blksz, misc.blksz);
	if (!block || !readback) {
		liuqin_out_linef("misc: command buffer allocation failed");
		ret = -ENOMEM;
		goto out;
	}
	if (blk_dread(desc, first, 1, block) != 1) {
		liuqin_out_linef("misc: read failed at %llu",
				 (unsigned long long)first);
		ret = -EIO;
		goto out;
	}

	liuqin_bcb_command_text(block, command, sizeof(command));
	liuqin_out_linef("misc: command %s", command[0] ? command : "<empty>");
	if (memcmp(block, LIUQIN_BCB_BOOTONCE, command_len) ||
	    block[command_len])
		goto out;

	liuqin_out_linef("misc: clearing stale bootonce-bootloader");
	memset(block, 0, LIUQIN_BCB_COMMAND_BYTES);
	if (blk_dwrite(desc, first, 1, block) != 1) {
		liuqin_out_linef("misc: command write failed at %llu",
				 (unsigned long long)first);
		ret = -EIO;
		goto out;
	}
	if (liuqin_scsi_sync_cache(desc)) {
		liuqin_out_linef("misc: command write was not flushed");
		ret = -EIO;
		goto out;
	}
	if (blk_dread(desc, first, 1, readback) != 1 ||
	    memcmp(readback, block, misc.blksz)) {
		liuqin_out_linef("misc: command clear read-back failed");
		ret = -EIO;
		goto out;
	}
	liuqin_out_linef("misc: bootonce-bootloader cleared and flushed");

out:
	free(block);
	free(readback);
	liuqin_gpt_free(&misc);

	return ret;
}

/*
 * The failure landing pad for the two menu actions: dump everything known about
 * this table on the panel, then stay there instead of returning to the menu.
 *
 * The bootmenu redraws the screen the moment an entry returns, so a failed
 * action used to flash its reason past the operator in well under a second -
 * and with no UART the panel is the only log this board has. Here the whole
 * picture is printed in reading order (the steps the write path recorded, then
 * the table as it is on disk right now, re-read) and the board then parks.
 *
 * Parking keeps calling schedule(), so the cyclic callback that pets the Gunyah
 * vWDT keeps running: a bare spin would have the board reset itself after the
 * 60 s bark, which would throw the message away - exactly what this exists to
 * prevent. Leave with the power button (or a power cycle).
 */
void liuqin_ab_hold(const char *op)
{
	struct liuqin_gpt g = {0};
	struct udevice *dev;
	int show;

	/* Everything from here on is meant to be read off the panel. */
	liuqin_quiet = false;

	printf("\n=== %s FAILED ===\n", op);

	/* 1. The steps the write path recorded, oldest first. */
	show = liuqin_ring_lines();
	if (show > LIUQIN_RING_SHOW)
		show = LIUQIN_RING_SHOW;
	printf("--- write path, %d of %d lines ---\n", show,
	       liuqin_ring_lines());
	liuqin_ring_print(show);

	/* 2. What U-Boot enumerated at all: a failure that reports "no GPT holds
	 * boot_a" has to be read against this. */
	printf("--- UFS LUNs ---\n");
	for (uclass_first_device(UCLASS_BLK, &dev); dev;
	     uclass_next_device(&dev)) {
		struct blk_desc *d = dev_get_uclass_plat(dev);

		if (!d || d->uclass_id != UCLASS_SCSI)
			continue;
		printf("lun%d blksz %lu last-blk %llu\n", d->lun, (ulong)d->blksz,
		       (unsigned long long)d->lba);
	}

	/* 3. The table as it is on disk now (read-only). Everything below also
	 * goes into the ring, so fastboot.gpt* carries the same bytes the panel
	 * shows. */
	printf("--- table, read back from disk ---\n");
	if (liuqin_gpt_holding(&g, "boot_a")) {
		gpt_entry *xbl = liuqin_gpt_find(&g, "xbl_sc_logs");
		gpt_entry *tail = liuqin_gpt_find(&g, "last_parti");

		liuqin_gpt_dump(g.desc, GPT_PRIMARY_PARTITION_TABLE_LBA, "pri");
		liuqin_gpt_dump(g.desc, le64_to_cpu(g.hdr->alternate_lba), "bak");
		if (xbl)
			liuqin_out_linef("xbl_sc_logs %llu..%llu idx%llu",
					 (unsigned long long)le64_to_cpu(xbl->starting_lba),
					 (unsigned long long)le64_to_cpu(xbl->ending_lba),
					 (unsigned long long)liuqin_gpt_index(&g, xbl));
		else
			liuqin_out_linef("xbl_sc_logs absent");
		if (tail)
			liuqin_out_linef("last_parti %llu..%llu idx%llu type:%s",
					 (unsigned long long)le64_to_cpu(tail->starting_lba),
					 (unsigned long long)le64_to_cpu(tail->ending_lba),
					 (unsigned long long)liuqin_gpt_index(&g, tail),
					 liuqin_ent_unused(tail) ? "empty" : "USED");
		else
			liuqin_out_linef("last_parti absent");
		liuqin_slot_attr_lines(&g);
		liuqin_gpt_free(&g);
	} else {
		liuqin_out_linef("no CRC-valid primary GPT holds boot_a");
	}
	printf("--- end of detail ---\n");
	printf("staying here on purpose: photograph now, power-cycle to leave\n");

	for (;;) {
		schedule();
		mdelay(500);
	}
}

/* The two slots' state bytes, as the panel, the ring and the probe print them. */
void liuqin_slot_attr_lines(const struct liuqin_gpt *g)
{
	int i;

	for (i = 0; i < 2; i++) {
		char name[8];
		gpt_entry *ent;
		u64 at;

		snprintf(name, sizeof(name), "boot_%c", i ? 'b' : 'a');
		ent = liuqin_gpt_find(g, name);
		if (!ent) {
			liuqin_out_linef("%s: absent from the table", name);
			continue;
		}
		at = liuqin_ent_attrs(ent);
		liuqin_out_linef("%s attrs %04llx pri%llu %s tries%llu %s %s",
				 name, (unsigned long long)(at >> 48),
				 (unsigned long long)((at >> 48) & 3),
				 (at >> 50) & 1 ? "active" : "-",
				 (unsigned long long)((at >> 51) & 7),
				 (at >> 54) & 1 ? "successful" : "-",
				 (at >> 55) & 1 ? "UNBOOTABLE" : "-");
	}
}

static int do_liuqin_setactive(struct cmd_tbl *cmdtp, int flag, int argc,
			       char *const argv[])
{
	char buf[32];
	const char *slot;
	bool hold, reset;
	int ret;

	if (argc < 2)
		return CMD_RET_USAGE;
	slot = liuqin_arg_slot(argv[1]);
	if (!slot) {
		printf("slot: expected a or b, got \"%s\"\n", argv[1]);
		return CMD_RET_USAGE;
	}
	if (*slot != 'a') {
		printf("slot: selecting boot_b is an ABL-fastboot operation\n");
		return CMD_RET_FAILURE;
	}

	/*
	 * "hold" (bootmenu only) keeps a failure on the panel with the whole
	 * picture instead of letting the menu redraw it away; "reset" reboots on
	 * success, which is what "boot Android" wants. The paths a host can reach
	 * (the fastboot hook) pass neither, so nothing can hang a host.
	 */
	hold = liuqin_arg_present(argc, argv, "hold");
	reset = liuqin_arg_present(argc, argv, "reset");

	liuqin_out_reset();
	ret = liuqin_ab_commit_slot(*slot, false, LIUQIN_SLOT_SELECT);
	snprintf(buf, sizeof(buf), ret ? "switching to %c failed" : "%c active",
		 *slot);
	env_set("fastboot.slot", buf);

	if (ret) {
		if (hold)
			liuqin_ab_hold("liuqin_setactive a");
		return CMD_RET_FAILURE;
	}

	if (reset) {
		/*
		 * do_reset() parses the command's own argv and rejects more than
		 * two arguments. argv here belongs to liuqin_setactive ("a hold
		 * reset"), so passing argc through makes the reset path return
		 * CMD_RET_USAGE and bootmenu immediately redraws itself. Invoke
		 * reset with the one-argument "reset" command shape.
		 */
		char *reset_argv[] = { "reset", NULL };

		ret = liuqin_normal_reboot();
		if (ret < 0) {
			printf("slot: normal hand-off reason could not be cleared\n");
			liuqin_ab_hold("liuqin_setactive normal hand-off");
			return CMD_RET_FAILURE;
		}
		/* A working SCM conduit does not return. If firmware returned an
		 * error, the PMIC/reason pair is nevertheless valid, so retain
		 * the old PSCI fallback rather than leaving the board at the
		 * menu. */
		ret = do_reset(cmdtp, flag, 1, reset_argv);
		printf("slot: reset returned unexpectedly (%d)\n", ret);
		liuqin_ab_hold("liuqin_setactive reset");
		return CMD_RET_FAILURE;
	}

	return CMD_RET_SUCCESS;
}

U_BOOT_CMD(liuqin_setactive, 4, 0, do_liuqin_setactive,
	"make Android A the slot ABL boots",
	"<a> [hold] [reset] - set boot_a priority/active and demote boot_b;\n"
	"  \"reset\" reboots on success (what \"boot Android\" wants), \"hold\"\n"
	"  keeps a failure - with every detail behind it - on the panel until\n"
	"  the board is power-cycled, so it can be read or photographed");

/*
 * The one slot decision this image cannot make on its own: whether the payload
 * in a slot has proved that it boots. A persistent boot of that slot and an ABL
 * RAM boot hand over the same /chosen/bootargs slot string, so no runtime
 * evidence distinguishes them and the claim stays a human action from the
 * bootmenu (docs/FACTS.md §2).
 *
 * The cost of the claim belongs on the panel: a successful slot stops being
 * counted against its retry budget, so a payload in it that later cannot boot
 * is never called unbootable and ABL never falls back to the other slot.
 */
static int do_liuqin_mark_successful(struct cmd_tbl *cmdtp, int flag, int argc,
				     char *const argv[])
{
	char buf[32], running[8];
	const char *slot;
	bool hold;
	int ret;

	if (argc < 2)
		return CMD_RET_USAGE;
	slot = liuqin_arg_slot(argv[1]);
	if (!slot) {
		printf("mark: expected a or b, got \"%s\"\n", argv[1]);
		return CMD_RET_USAGE;
	}
	hold = liuqin_arg_present(argc, argv, "hold");
	liuqin_out_reset();

	/* Worth saying out loud rather than refusing: ABL points at another
	 * slot, so this execution did not come from the slot being marked. */
	if (!fastboot_current_slot(running, sizeof(running)) &&
	    *running != *slot)
		liuqin_outf("mark: ABL points at %s, not %c", running, *slot);

	ret = liuqin_ab_commit_slot(*slot, true, LIUQIN_SLOT_MARK);
	snprintf(buf, sizeof(buf), ret ? "%c successful: failed" :
		 "%c successful", *slot);
	env_set("fastboot.slot", buf);

	if (ret && hold)
		liuqin_ab_hold("liuqin_mark_successful b");

	return ret ? CMD_RET_FAILURE : CMD_RET_SUCCESS;
}

U_BOOT_CMD(liuqin_mark_successful, 3, 0, do_liuqin_mark_successful,
	"record that a slot's payload boots (bootmenu action)",
	"<a|b> [hold] - boot_<slot> gets prio 3 + active + tries 7 + successful,\n"
	"  the other slot is demoted; both GPT copies are written and read back;\n"
	"  \"hold\" (bootmenu only) keeps a failure on the panel with every\n"
	"  detail behind it until the board is power-cycled.\n"
	"  ABL then stops spending that slot's retry budget and no longer falls\n"
	"  back to the other slot when it cannot boot - only claim it for a slot\n"
	"  whose persistent payload has been shown to boot.");

/*
 * fastboot protocol hooks (see include/fastboot.h). The generic versions know
 * nothing about this board's slot state: upstream answers OKAY to "set_active"
 * without doing anything and reports the constant "a" for "current-slot" - so
 * the host would believe a slot switch that never happened. "has-slot" is what
 * the stock client asks first: it refuses to send "set_active" at all until
 * that answers yes for the boot partition.
 */
int fastboot_set_active_slot(const char *slot)
{
	slot = liuqin_arg_slot(slot ? slot : "");
	if (!slot)
		return -EINVAL;
	/* U-Boot is never installed by this image. Its fastboot endpoint may
	 * perform the explicit Android handoff to A, but cannot promote B. */
	if (*slot != 'a')
		return -EPERM;

	liuqin_out_reset();

	return liuqin_ab_commit_slot(*slot, false, LIUQIN_SLOT_SELECT);
}

/*
 * U-Boot's generic fastboot handler used to call PSCI directly for
 * `fastboot reboot`. On liuqin that skips the vendor PMIC/SCM normal-reset
 * sequence, so make the host-side set_active + reboot path identical to the
 * menu's Android hand-off. If the hand-off state cannot be prepared, stay in
 * U-Boot: a bare reset would carry the inherited ABL-fastboot reason straight
 * back into fastboot. Only a valid reason/PMIC setup followed by an SCM call
 * that unexpectedly returns is allowed to use PSCI as a last resort.
 */
void fastboot_reboot(void)
{
	int ret = liuqin_normal_reboot();

	if (ret < 0) {
		printf("fastboot: normal hand-off setup failed (%d), staying in U-Boot\n",
		       ret);
		return;
	}
	if (ret > 0)
		printf("fastboot: SCM returned, using PSCI fallback\n");
	do_reset(NULL, 0, 0, NULL);
}

/*
 * The generic has-slot implementation goes through the MMC flash backend, which
 * this board does not use: its slotted partitions live in the GPT of a UFS LUN,
 * and liuqin_gpt_holding() already finds a partition by name across the LUNs.
 */
int fastboot_has_slot(const char *part)
{
	struct liuqin_gpt g = {0};
	char name[PART_NAME_LEN];
	int i, ret = 0;

	if (!part || !*part)
		return -EINVAL;

	/* "<part>_a" first: that is the half has-slot is defined in terms of. */
	for (i = 0; i < 2 && !ret; i++) {
		if (snprintf(name, sizeof(name), "%s_%c", part,
			     i ? 'b' : 'a') >= (int)sizeof(name))
			return -EINVAL;
		if (liuqin_gpt_holding(&g, name)) {
			liuqin_gpt_free(&g);
			ret = 1;
		}
	}

	return ret;
}

int fastboot_current_slot(char *buf, size_t size)
{
	struct liuqin_gpt g = {0};
	u64 a, b;
	gpt_entry *ent_a, *ent_b;
	bool a_ok, b_ok;

	if (!liuqin_gpt_holding(&g, "boot_a"))
		return -ENOENT;

	ent_a = liuqin_gpt_find(&g, "boot_a");
	ent_b = liuqin_gpt_find(&g, "boot_b");
	if (!ent_a || !ent_b) {
		liuqin_gpt_free(&g);
		return -ENOENT;
	}
	a = liuqin_ent_attrs(ent_a);
	b = liuqin_ent_attrs(ent_b);
	liuqin_gpt_free(&g);

	/* The same rule ABL applies: ignore unbootable/zero-priority slots, then
	 * prefer the sole active slot, then the higher priority. */
	a_ok = !(a & LIUQIN_SLOT_UNBOOTABLE) && !!(a & LIUQIN_SLOT_PRIO_MASK);
	b_ok = !(b & LIUQIN_SLOT_UNBOOTABLE) && !!(b & LIUQIN_SLOT_PRIO_MASK);
	if (a_ok && !b_ok)
		snprintf(buf, size, "a");
	else if (b_ok && !a_ok)
		snprintf(buf, size, "b");
	else if (!!(a & LIUQIN_SLOT_ACTIVE) != !!(b & LIUQIN_SLOT_ACTIVE))
		snprintf(buf, size, "%c", (a & LIUQIN_SLOT_ACTIVE) ? 'a' : 'b');
	else
		snprintf(buf, size, "%c",
			 (a & LIUQIN_SLOT_PRIO_MASK) >=
					 (b & LIUQIN_SLOT_PRIO_MASK) ? 'a' : 'b');

	return 0;
}
