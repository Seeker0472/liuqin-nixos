# SPDX-License-Identifier: MIT
#
# LED class devices have no /dev node, so udev's GROUP/MODE/uaccess cannot
# reach them; adjust the brightness attribute itself.  The flash LED belongs
# to the camera stack's group; the keyboard-backlight LED is the folio's only
# session-facing brightness control (GNOME has no keyboard-backlight UI and
# this port runs no UPower).
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin;
in
{
  config = lib.mkIf cfg.enable {
    services.udev.extraRules = ''
      SUBSYSTEM=="leds", KERNEL=="white:flash", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/leds/white:flash/brightness", RUN+="${pkgs.coreutils}/bin/chmod 0664 /sys/class/leds/white:flash/brightness"
      SUBSYSTEM=="leds", KERNEL=="liuqin-keyboard::kbd_backlight", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/leds/liuqin-keyboard::kbd_backlight/brightness", RUN+="${pkgs.coreutils}/bin/chmod 0664 /sys/class/leds/liuqin-keyboard::kbd_backlight/brightness"
    '';
  };
}
