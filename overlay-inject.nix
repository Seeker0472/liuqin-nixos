# SPDX-License-Identifier: MIT
#
# Re-point the device-specific packages at an existing x86_64 -> aarch64 cross
# package set.
#
# The cross outputs are aarch64 artifacts exactly like native ones, so any
# aarch64 system can use them directly. That matters because cache.nixos.org
# only carries *native* aarch64 builds: a cross-built derivation is a different
# derivation with a different hash, so the cross package set has no cache
# entries at all and building a whole desktop from it means compiling every
# dependency locally.
#
# Used by the repo's installed configurations (`injectFrom = pkgsArm`, see
# flake.nix) and by consumers (`injectFrom = liuqin.lib.pkgsArm`): the x86_64
# host cross-builds just these packages once, and the native aarch64 system -
# whose remaining parts, GNOME included, come from cache.nixos.org - reuses
# those artifacts. Building the per-machine derivations (/etc, units, initrd)
# still needs an aarch64 executor: binfmt on the host, or the device itself.
#
# The list itself is not kept here: pkgs/device-packages.nix is the single
# classification registry (what is injected, what is deliberately native, and
# why), shared with the flake's liuqin-package-manifest check.
{ pkgsArm }:

_final: _prev:

let
  manifest = import ./pkgs/device-packages.nix;
in
builtins.listToAttrs (
  map (name: { inherit name; value = pkgsArm.${name}; }) manifest.inject
)
