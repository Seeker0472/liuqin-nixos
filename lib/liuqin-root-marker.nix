# SPDX-License-Identifier: MIT
#
# The persistent-root identity marker: the single source of truth for the
# bytes the initrd storage guard verifies.  Both consumers derive from this
# file - the guard (modules/liuqin/initrd-guard.nix) and the activation script
# that provisions /etc/liuqin-nixos-root (same module, so nixos-install and
# every later nixos-rebuild write it) - so the two cannot drift.  A mismatch
# would make the guard fail the first boot before tmpfiles gets a chance to
# repair the file.
{ lib }:
let
  content = "LIUQIN_NIXOS_ROOT_V1\n";
in
{
  inherit content;
  sha256 = builtins.hashString "sha256" content;
  size = builtins.stringLength content;
  # For single-line consumers (tmpfiles, printf): the trailing newline has to
  # be the two-character escape \n.  A raw newline would silently truncate
  # the written file to 20 bytes instead of 21.
  escaped = lib.replaceStrings [ "\n" ] [ "\\n" ] content;
}
