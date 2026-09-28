# SPDX-License-Identifier: MIT
#
# Login program for the USB control channel's telnetd: an interactive busybox
# shell. Shared by the RAM installer (config/installer.nix) and the installed
# system's debug channel (modules/liuqin/usb-shell.nix).
{ writeShellApplication, busybox }:

writeShellApplication {
  name = "liuqin-usb-login";
  runtimeInputs = [ busybox ];
  text = ''
    exec busybox sh -i "$@"
  '';
}
