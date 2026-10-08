# SPDX-License-Identifier: MIT
#
# Point the kernel's firmware loader at one directory.
#
# `firmware_class.path` (drivers/base/firmware_loader/main.c) is a single
# char[256] with no ':' splitting, so it names exactly one tree, and the value
# must carry no trailing newline - printf writes the argument byte for byte.
# The unit that runs this (modules/liuqin/firmware.nix) orders it after
# run-firmware.mount: until the union exists the loader keeps the path NixOS's
# activation script wrote (the hardware.firmware environment, which carries the
# AudioReach topology the ASoC card probe loads at ~10 s), and a mount that
# fails leaves that path in place instead of an empty directory.
{ writeShellApplication }:

writeShellApplication {
  name = "liuqin-firmware-loader-path";

  text = ''
    if [ "$#" -ne 1 ]; then
      echo "usage: liuqin-firmware-loader-path DIRECTORY" >&2
      exit 2
    fi
    case $1 in
      /*) ;;
      *)
        echo "liuqin-firmware-loader-path: the loader path must be absolute" >&2
        exit 2
        ;;
    esac

    # A sysfs write replaces the value whole; only the bytes written matter.
    printf '%s' "$1" > /sys/module/firmware_class/parameters/path
  '';
}
