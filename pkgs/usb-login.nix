# SPDX-License-Identifier: MIT
#
# Login program for the USB control channel's telnetd: an interactive busybox
# shell. Shared by the RAM installer (config/installer.nix) and the installed
# system's debug channel (modules/liuqin/usb-shell.nix).
{ writeShellApplication, busybox }:

writeShellApplication {
  name = "liuqin-usb-login";
  # No runtimeInputs and the system profile put first: the shell must take
  # its tools from the system, not from any single package. Two things this
  # gets wrong otherwise: prepending busybox makes `reboot` resolve to the
  # busybox applet, which when it is not PID 1 only signals init and is a
  # silent no-op under systemd (measured on the installed system: exit 0,
  # the session died, and nothing else happened, while `systemctl reboot`
  # restarts the board); and the PATH a systemd service hands to this shell
  # carries coreutils/findutils/grep/sed/systemd but neither dmesg nor nix,
  # so reading the journal or using nix needed absolute paths. The system
  # profile has all of it, including systemd's own `reboot`.
  text = ''
    export PATH=/run/current-system/sw/bin:$PATH
    exec ${busybox}/bin/busybox sh -i "$@"
  '';
}
