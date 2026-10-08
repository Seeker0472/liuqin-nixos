# SPDX-License-Identifier: MIT
#
# Single classification registry for the packages overlay.nix defines.
#
# `nix flake check` asserts (checks.liuqin-package-manifest) that the names
# below cover overlay.nix's definitions exactly, so adding or removing a
# package there fails the check until it is classified here - the two lists
# cannot silently drift apart.
#
#   inject  built once by the flake's x86_64 -> aarch64 cross set (pkgsArm),
#           re-exported by overlay-inject.nix, and reused by a native aarch64
#           system.  For device packages that are expensive or awkward to
#           build on the target.
#
#   native  built by whatever package set the overlay is applied to.  For
#           single-shot shell commands, data-only leaves, and packages whose
#           cross build would drag the build host's desktop in.  Each entry
#           carries its reason.
#
# The flake's allowUnfreePredicate matches derivation names against `unfree`:
# nixpkgs' requireFile marks its fixed-output derivations unfree, so every
# operator-supplied payload counts here (pkgs/firmware.nix,
# pkgs/sensors-config.nix, pkgs/bootimg/stock-*.nix).
let
  fpcReason = "OEM FPC1264 stack: built natively today; the cross path in overlay.nix is unexercised, and injecting would change the installed closure";
in
{
  inject = [
    # Kernel and its boot-chain artifacts.
    "liuqinKernel"
    "liuqinInstallerKernel"
    "liuqinKernelDtb"
    "liuqinInstallerKernelDtb"
    "mkbootimg"
    "liuqinBootimg"
    "liuqinUboot"
    # Libraries and daemons the installed system always carries.
    "liuqinLibcameraAf"
    "liuqinCamAf"
    "liuqinMippsd"
    "liuqinHexagonrpc"
    "liuqinSensorsConfig"
    "liuqinIioSensorProxy"
    # Firmware trees.
    "liuqinFirmware"
    "liuqinInitrdFirmware"
  ];

  native = {
    # Cross-building this one substitutes a store path from the build host's
    # gnome-control-center into its menu script and thereby pulls the entire
    # cross GNOME closure into the device system; natively it is three files
    # of C and shell.
    liuqinPowerKeyd = "cross would pull the cross GNOME closure into the device system";
    # Single-shot shell commands and data leaves with no closure of their own.
    liuqinScreenRefresh = "shell script";
    liuqinBacklightDefault = "shell script";
    liuqinPersistProvision = "shell script";
    liuqinWlanMac = "shell script";
    liuqinBtPublicAddr = "shell script";
    liuqinBtNv = "manual BT NV/RF table writer, run by hand";
    liuqinSlpi = "shell script";
    liuqinSensorProxyRefresh = "shell script";
    liuqinUsbLogin = "shell script";
    liuqinStorageGuard = "shell script (fail-closed fixture tests in its checkPhase)";
    mkLiuqinUsbGadget = "configfs gadget shell factory, parameterised per consumer";
    liuqinSensorCheck = "bounded manual sensor-acceptance client, not in any unit";
    liuqinAlsaUcm = "data-only leaf (UCM2 files)";
    liuqinGnomeFlashlight = "data-only leaf (GNOME Shell extension files)";
    # OEM FPC1264 fingerprint stack.
    liuqinFpcOemLibfprintTod = fpcReason;
    liuqinFpcOemSrc = "vendored OEM component source tree (a path, not a package)";
    liuqinFpcOemQcbor = fpcReason;
    liuqinFpcOemSupplicant = fpcReason;
    liuqinFpcOemTodDriver = fpcReason;
    liuqinFpcOem = fpcReason;
    liuqinPamFpc = fpcReason;
    liuqinFprintdOem = fpcReason;
  };

  unfree = [
    "liuqin-ssc-config.tar.zst"
    "liuqin-firmware-vpu.tar.zst"
    "liuqin-firmware-cs35l41.tar.zst"
    "stock-base-dtbs.tar.zst"
    "stock-dtbo-entries.tar.zst"
    "boot.img"
  ];
}
