# SPDX-License-Identifier: MIT
#
# Point the kernel firmware loader at one directory that carries every
# firmware tree this board needs.
#
# The loader reads exactly one directory (firmware_class.path; fw_path_para is
# a single char[256] with no ':' splitting, see
# drivers/base/firmware_loader/main.c) and /lib/firmware does not exist on
# NixOS.  Three trees must be reachable, with a fixed precedence:
#
#   - ${liuqinFirmware}/lib/firmware: the vendor's CS35L41 payloads, which
#     must shadow linux-firmware's same-named files in the system tree;
#   - /run/current-system/firmware: the system firmware tree (ADSP/CDSP/SLPI,
#     the AudioReach topology, everything else);
#   - /var/lib/firmware: the per-device CS35L41 calibration records that
#     liuqin-persist-provision.service writes out of the persist partition
#     (they cannot live in the store).
#
# An overlay mount merges the three recursively, the leftmost lowerdir winning
# on name collisions, so mount it read-only and write the union into the
# loader parameter.  The service runs before sound.target; a missing
# calibration record only warns (the CS35L41 protection gate is supposed to
# stay closed without it), while a missing store tree fails the mount.
{ writeShellApplication, coreutils, util-linux, liuqinFirmware }:

writeShellApplication {
  name = "liuqin-firmware-path";

  runtimeInputs = [ coreutils util-linux ];

  text = ''
    union_dir=/run/firmware
    loader_path=/sys/module/firmware_class/parameters/path
    lowerdir=${liuqinFirmware}/lib/firmware:/run/current-system/firmware:/var/lib/firmware

    mkdir -p /var/lib/firmware "$union_dir"
    mount -t overlay overlay -o "ro,lowerdir=$lowerdir" "$union_dir"
    echo -n "$union_dir" > "$loader_path"

    if [ ! -e "$union_dir/cirrus/cs35l41-liuqin-TL-calr.bin" ]; then
      echo "liuqin-firmware-path: no CS35L41 calibration in the union;" >&2
      echo "  liuqin-persist-provision.service must provision it from persist" >&2
    fi
  '';
}
