# SPDX-License-Identifier: MIT
#
# Force the known-good desktop backlight level after systemd-backlight@
# restored whatever the last session left (modules/liuqin/hardware.nix orders
# the unit accordingly). The panel is this board's only boot evidence, so the
# write is verified instead of assumed.
#
# Charger mode is not handled here: the unit skips itself with a
# ConditionKernelCommandLine, so a manual run of this command always sets the
# level.
#
# `--root` exists so the level logic can be exercised against a fake sysfs
# tree; the unit uses the default.
{ writeShellApplication, coreutils }:

writeShellApplication {
  name = "liuqin-backlight-default";

  runtimeInputs = [ coreutils ];

  text = ''
    root=/sys/class/backlight
    device=ktz8866-backlight
    level=1500
    max=2047

    while [ "$#" -gt 0 ]; do
      case $1 in
        --root|--device|--level|--max)
          if [ "$#" -lt 2 ]; then
            echo "usage: liuqin-backlight-default [--root DIR] [--device NAME] [--level N] [--max N]" >&2
            exit 2
          fi
          case $1 in
            --root) root=$2 ;;
            --device) device=$2 ;;
            --level) level=$2 ;;
            --max) max=$2 ;;
          esac
          shift 2
          ;;
        *)
          echo "usage: liuqin-backlight-default [--root DIR] [--device NAME] [--level N] [--max N]" >&2
          exit 2
          ;;
      esac
    done

    backlight=$root/$device
    # A different panel means the constants above were never verified on it.
    [ -d "$backlight" ]
    [ "$(cat "$backlight/max_brightness")" = "$max" ]
    echo "$level" > "$backlight/brightness"
    echo 0 > "$backlight/bl_power"
    [ "$(cat "$backlight/actual_brightness")" = "$level" ]
    [ "$(cat "$backlight/brightness")" = "$level" ]
    [ "$(cat "$backlight/bl_power")" = 0 ]
  '';
}
