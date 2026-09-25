# SPDX-License-Identifier: MIT
#
# Firmware needed while the netboot initrd is still running. Keep this
# separate from the full device firmware tree: the initrd must be able to
# bring up ath11k before switch_root, but it does not need DSP, GPU, VPU,
# touchscreen, or Bluetooth payloads just to mount the live root - and the
# touchscreen stays out on purpose.  Without its firmware nvt_ts_resume()
# closes the device on the first blank/unblank ("resume failed closed: -2"),
# but the installer's panel is an output-only fallback channel (there is no
# keyboard to type on it), so the payload buys nothing here; the installed
# system carries the full firmware set and does have touch.
{ runCommand, firmware }:

runCommand "liuqin-initrd-firmware" { } ''
  mkdir -p "$out/lib/firmware"

  cp -a ${firmware}/lib/firmware/ath11k "$out/lib/firmware/"
  mkdir -p "$out/lib/firmware/updates"
  cp -a ${firmware}/lib/firmware/updates/ath11k "$out/lib/firmware/updates/"
  install -Dm0644 ${firmware}/lib/firmware/regulatory.db \
    "$out/lib/firmware/regulatory.db"
  install -Dm0644 ${firmware}/lib/firmware/regulatory.db.p7s \
    "$out/lib/firmware/regulatory.db.p7s"
''
