# SPDX-License-Identifier: MIT
#
# One blank/unblank of the framebuffer makes fbcon redraw its whole console
# buffer - scrollback included - into the memory the panel scans. The RAM
# installer runs it once during boot (config/installer.nix); the installed
# system's unit is gone (modules/liuqin/display.nix).
#
# `--graphics-dir` exists so the blank sequence can be exercised against a
# fake sysfs tree; the unit uses the default.
{ writeShellApplication, coreutils }:

writeShellApplication {
  name = "liuqin-screen-refresh";

  runtimeInputs = [ coreutils ];

  text = ''
    graphics_dir=/sys/class/graphics
    while [ "$#" -gt 0 ]; do
      case $1 in
        --graphics-dir)
          if [ "$#" -lt 2 ]; then
            echo "usage: liuqin-screen-refresh [--graphics-dir DIR]" >&2
            exit 2
          fi
          graphics_dir=$2
          shift 2
          ;;
        *)
          echo "usage: liuqin-screen-refresh [--graphics-dir DIR]" >&2
          exit 2
          ;;
      esac
    done

    # A missing fb node is not an error: the service also runs on boots where
    # the display stack never got as far as registering a framebuffer.
    for blank in "$graphics_dir"/fb*/blank; do
      [ -e "$blank" ] || continue
      echo 1 > "$blank"
      sleep 1
      echo 0 > "$blank"
    done
  '';
}
