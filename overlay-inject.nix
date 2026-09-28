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
# Applied via `mkLiuqinSystem { injectFrom = ...; }`, passing the flake's own
# `pkgsArm`. A consumer building on a real aarch64 host should leave it unset.
#
# liuqinPowerKeyd is deliberately NOT injected: pkgs/power-keyd.nix substitutes
# a path from gnome-control-center into its menu helper, and the cross build of
# that package therefore drags the entire *cross* GNOME desktop (mutter,
# webkitgtk, ...) into the installed system's closure - cross derivations no
# cache can serve.  Built natively it is three files of C and shell and points
# at the native gnome-control-center the GNOME desktop already carries.
{ pkgsArm }:

_final: _prev:
{
  inherit (pkgsArm)
    liuqinKernel
    liuqinInstallerKernel
    liuqinKernelDtb
    liuqinInstallerKernelDtb
    mkbootimg
    liuqinBootimg
    liuqinUboot
    liuqinHexagonrpc
    liuqinSensorsConfig
    liuqinLibssc
    liuqinIioSensorProxy
    liuqinFirmware
    liuqinInitrdFirmware
    ;
}
