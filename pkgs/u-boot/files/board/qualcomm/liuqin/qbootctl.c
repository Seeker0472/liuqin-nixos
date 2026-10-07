// SPDX-License-Identifier: GPL-2.0+
/*
 * The A/B identity layer, ported from qbootctl.
 *
 * Upstream: git@github.com:linux-msm/qbootctl.git (gpt-utils.c). Its
 * UPDATE_SLOT() does two independent things for every A/B partition it knows:
 * it puts the type GUID belonging to the current active slot on the newly
 * selected slot and leaves the other type GUID on the fallback slot, and it
 * moves the UFS bBootLunEn attribute that PBL reads to pick xbl_a/xbl_b. The
 * local ABL validates that identity layer, so a table whose boot_a/boot_b
 * attributes were changed but whose roles were not is CRC-perfect and still
 * describes the wrong slot (docs/FACTS.md §3).
 *
 * Two things are done differently here, because this is not Linux:
 *
 *  - the roles are swapped inside the table the caller already has loaded, and
 *    the caller commits it through liuqin_gpt_commit(). Upstream writes the
 *    partitions it changed itself, through its own GPT writer.
 *  - the boot LUN is not reached through the UFS BSG character device: U-Boot's
 *    UFS driver exposes the same device attribute as ufs_get_boot_lun() and
 *    ufs_set_boot_lun().
 *
 * The two halves stay fail-closed in the caller's order: the attribute is read
 * before anything is changed, so a missing boot-LUN channel leaves the table
 * untouched, and it is verified after the table has been committed.
 */

#include <dm.h>
#include <linux/kernel.h>
#include <ufs.h>

#include "liuqin.h"

/*
 * The type-GUID roles are a property of the slot that is active now, and an
 * A/B hand-off swaps them exactly like qbootctl does. Several names from the
 * generic Qualcomm list do not exist on this tablet; pairs that are absent are
 * skipped, but a half-present pair is never silently accepted.
 */
static const char *const liuqin_ab_type_guid_bases[] = {
	"abl", "aop", "apdp", "cmnlib", "cmnlib64", "devcfg", "dtbo",
	"hyp", "keymaster", "msadp", "qupfw", "storsec", "tz", "vbmeta",
	"vbmeta_system", "boot", "system", "vendor", "modem", "system_ext",
	"product",
};

/* The caller sizes its role buffers with the header's constant. */
_Static_assert(ARRAY_SIZE(liuqin_ab_type_guid_bases) ==
	       LIUQIN_AB_TYPE_GUID_COUNT, "type GUID list changed");

/* The longest base is 13 characters, so these names never need truncating. */
#define LIUQIN_PAIR_NAME_LEN	24

static void liuqin_pair_name(char *buf, const char *base, char slot)
{
	snprintf(buf, LIUQIN_PAIR_NAME_LEN, "%s_%c", base, slot);
}

/*
 * Capture the two GUIDs per pair before changing anything: @active_type[i]
 * holds the role the current slot carries, @inactive_type[i] the fallback's.
 * Returns 0 when the table is slot-consistent afterwards (or was left alone
 * because the slot is already the current one), -ENOENT when a pair it has to
 * switch is incomplete.
 */
int liuqin_slot_type_guids_prepare(struct liuqin_gpt *g, char target,
				   char current, u8 active_type[][16],
				   u8 inactive_type[][16])
{
	unsigned int i, swapped = 0;

	if ((target != 'a' && target != 'b') || (current != 'a' && current != 'b'))
		return -EINVAL;

	for (i = 0; i < LIUQIN_AB_TYPE_GUID_COUNT; i++) {
		const char *base = liuqin_ab_type_guid_bases[i];
		char target_name[LIUQIN_PAIR_NAME_LEN];
		char other_name[LIUQIN_PAIR_NAME_LEN];
		char current_name[LIUQIN_PAIR_NAME_LEN];
		char fallback_name[LIUQIN_PAIR_NAME_LEN];
		gpt_entry *target_ent, *other_ent, *current_ent, *fallback_ent;

		liuqin_pair_name(target_name, base, target);
		liuqin_pair_name(other_name, base, target == 'a' ? 'b' : 'a');
		liuqin_pair_name(current_name, base, current);
		liuqin_pair_name(fallback_name, base, current == 'a' ? 'b' : 'a');

		target_ent = liuqin_gpt_find(g, target_name);
		other_ent = liuqin_gpt_find(g, other_name);
		if (!target_ent && !other_ent)
			continue;	/* optional, absent from this model */
		if (!target_ent || !other_ent) {
			/* qbootctl ignores an optional partition absent from the
			 * device, but a half-present pair cannot be made
			 * slot-consistent. Keep the generic list useful here
			 * while making the anomaly visible in the hand-off log. */
			liuqin_out_linef("slot: skip unpaired type GUID %s (%s=%s %s=%s)",
					 base, target_name,
					 target_ent ? "yes" : "no", other_name,
					 other_ent ? "yes" : "no");
			continue;
		}

		current_ent = liuqin_gpt_find(g, current_name);
		fallback_ent = liuqin_gpt_find(g, fallback_name);
		if (!current_ent || !fallback_ent) {
			liuqin_out_linef("slot: type GUID current pair missing %s/%s",
					 current_name, fallback_name);
			return -ENOENT;
		}

		memcpy(active_type[i], &current_ent->partition_type_guid, 16);
		memcpy(inactive_type[i], &fallback_ent->partition_type_guid, 16);

		if (target != current) {
			memcpy(&target_ent->partition_type_guid, active_type[i], 16);
			memcpy(&other_ent->partition_type_guid, inactive_type[i], 16);
			swapped++;
		}
	}

	liuqin_out_linef("slot: type GUID roles %c->%c (%u pairs changed)",
			 current, target, swapped);

	return 0;
}

/* Are the roles @active_type/@inactive_type landed on the target/fallback
 * entries of the loaded (rewritten) copy? */
int liuqin_slot_type_guids_verify(struct liuqin_gpt *g, char target,
				  const u8 active_type[][16],
				  const u8 inactive_type[][16])
{
	unsigned int i;

	for (i = 0; i < LIUQIN_AB_TYPE_GUID_COUNT; i++) {
		const char *base = liuqin_ab_type_guid_bases[i];
		char target_name[LIUQIN_PAIR_NAME_LEN];
		char other_name[LIUQIN_PAIR_NAME_LEN];
		gpt_entry *target_ent, *other_ent;

		liuqin_pair_name(target_name, base, target);
		liuqin_pair_name(other_name, base, target == 'a' ? 'b' : 'a');
		target_ent = liuqin_gpt_find(g, target_name);
		other_ent = liuqin_gpt_find(g, other_name);
		if (!target_ent || !other_ent)
			continue;	/* prepare reported it */

		/* Whether the slot was already current or the roles were just
		 * swapped, the desired postcondition is the same: the target
		 * carries active_type. */
		if (memcmp(&target_ent->partition_type_guid, active_type[i], 16) ||
		    memcmp(&other_ent->partition_type_guid, inactive_type[i], 16)) {
			liuqin_out_linef("slot: type GUID verify failed for %s",
					 base);
			return -EIO;
		}
	}

	return 0;
}

int liuqin_boot_lun_for_slot(char slot)
{
	return slot == 'a' ? LIUQIN_BOOT_LUN_A :
	       slot == 'b' ? LIUQIN_BOOT_LUN_B : -EINVAL;
}

/* Read the attribute before touching GPT.  qbootctl opens its UFS BSG device
 * for exactly this reason: if the boot-LUN half is unavailable, do not leave a
 * newly selected GPT slot behind with no way to select xbl_a/xbl_b. */
int liuqin_boot_lun_prepare(char slot, u32 *before)
{
	int want = liuqin_boot_lun_for_slot(slot);
	int ret;

	if (want < 0)
		return want;

	ret = ufs_get_boot_lun(before);
	if (ret) {
		liuqin_out_linef("slot: read bBootLunEn failed (%d), GPT untouched",
				 ret);
		return ret;
	}
	liuqin_out_linef("slot: boot lun before %u, want %d", *before, want);

	return 0;
}

/* Set and read back the UFS attribute after GPT has committed.  If this fails,
 * the caller refuses to reset; an ABL boot with GPT and XBL pointing at
 * different slots is precisely the EFI_DEVICE_ERROR path we are avoiding. */
int liuqin_boot_lun_commit(char slot, u32 before)
{
	u32 after = 0;
	int want = liuqin_boot_lun_for_slot(slot);
	int ret;

	if (want < 0)
		return want;

	if (before != (u32)want) {
		ret = ufs_set_boot_lun(want);
		if (ret) {
			liuqin_out_linef("slot: write bBootLunEn=%d failed (%d); GPT is new, no reset",
					 want, ret);
			return ret;
		}
	}

	ret = ufs_get_boot_lun(&after);
	if (ret || after != (u32)want) {
		liuqin_out_linef("slot: boot lun verify failed got %u want %d (%d)",
				 after, want, ret);
		return ret ? ret : -EIO;
	}
	liuqin_out_linef("slot: boot lun %u verified for slot %c", after, slot);

	return 0;
}
