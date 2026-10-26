#!/system/bin/sh
# KernelSU runs this after Android reports boot completion. Slot B holds the
# liuqin U-Boot boot image; Android's own Boot Control HAL owns the hand-off.

report() {
    printf '%s\n' "liuqin-return-to-uboot: $1" >&2
    if [ -x /system/bin/log ]; then
        /system/bin/log -t liuqin-return-to-uboot "$1" >/dev/null 2>&1 || :
    fi
}

fail() {
    report "$1"
    exit 1
}

[ -x /system/bin/getprop ] || fail 'getprop unavailable; slot unchanged'
[ "$(/system/bin/getprop ro.product.device)" = liuqin ] ||
    fail 'device is not liuqin; slot unchanged'
[ "$(/system/bin/getprop sys.boot_completed)" = 1 ] ||
    fail 'Android boot is incomplete; slot unchanged'
[ "$(/system/bin/getprop ro.boot.slot_suffix)" = _a ] ||
    fail 'Android was not booted from slot A; slot unchanged'

bootctl=/data/adb/ksu/bin/bootctl
[ -x "$bootctl" ] || fail 'KernelSU bootctl unavailable; slot unchanged'
[ "$("$bootctl" hal-info)" = 'HAL Version: android.hardware.boot@1.2::IBootControl' ] ||
    fail 'unexpected Boot Control HAL; slot unchanged'
[ "$("$bootctl" get-number-slots)" = 2 ] ||
    fail 'Boot HAL did not report exactly two slots; slot unchanged'
[ "$("$bootctl" get-current-slot)" = 0 ] ||
    fail 'Boot HAL does not identify the booted slot as A; slot unchanged'
[ "$("$bootctl" get-suffix 1)" = _b ] ||
    fail 'Boot HAL does not identify slot 1 as B; slot unchanged'

# Require the boot-image magic U-Boot checks and a string compiled into this
# board's U-Boot payload. The payload is gzip-compressed and starts on page 1.
# This is an identity guard, not full image validation.
boot_b=/dev/block/by-name/boot_b
[ -b "$boot_b" ] || boot_b=/dev/block/bootdevice/by-name/boot_b
[ -b "$boot_b" ] || fail 'boot_b block device missing; slot unchanged'
[ "$(dd if="$boot_b" bs=8 count=1 2>/dev/null)" = 'ANDROID!' ] ||
    fail 'boot_b has no Android boot-image magic; slot unchanged'
dd if="$boot_b" bs=4096 skip=1 count=2048 2>/dev/null |
    gzip -dc 2>/dev/null |
    grep -a -F 'LIUQIN-UBOOT:' >/dev/null ||
    fail 'boot_b does not look like the liuqin U-Boot image; slot unchanged'

# The HAL, rather than a GPT-only writer, updates Qualcomm slot attributes,
# type-GUID roles and the UFS boot LUN. Never use get-current-slot for the
# post-write check: it reports the slot this Android session booted from.
active_before=$("$bootctl" get-active-boot-slot) ||
    fail 'could not read next boot slot; slot unchanged'
case "$active_before" in
    0|1) ;;
    *) fail 'invalid next boot slot reported; slot unchanged' ;;
esac

if ! "$bootctl" set-active-boot-slot 1; then
    fail 'Boot HAL rejected selection of slot B; inspect Android logs before reboot'
fi
sync || fail 'storage sync failed; do not reboot until inspected'

active_after=$("$bootctl" get-active-boot-slot) ||
    fail 'could not verify next boot slot; do not reboot until inspected'
[ "$active_after" = 1 ] ||
    fail 'next boot slot is not B after selection; do not reboot until inspected'
"$bootctl" is-slot-bootable 1 >/dev/null ||
    fail 'slot B is not bootable after selection; do not reboot until inspected'
report 'slot B selected and bootable; the next normal reboot enters U-Boot'
