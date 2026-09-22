# SPDX-License-Identifier: MIT
#
# Firmware needed while the netboot initrd is still running. Keep this
# separate from the full device firmware tree: the initrd must be able to
# bring up ath11k before switch_root, but it does not need DSP, GPU, VPU,
# touchscreen, or Bluetooth payloads just to mount the live root.
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
