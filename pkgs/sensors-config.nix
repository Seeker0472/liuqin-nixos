# SPDX-License-Identifier: MIT (this expression; see NOTICE for payloads)
#
# The SSC sensor configuration set hexagonrpcd serves to the SLPI
# (/usr/share/qcom/sm8450/Xiaomi/liuqin). The payloads are Qualcomm/Xiaomi
# proprietary binaries extracted from the stock ROM and are NOT
# redistributable by this repository, so this is a fixed-output derivation
# the operator materializes from their own device dump. See docs/PORTING-NOTES.md.
{ lib, runCommand, requireFile, sscConfigHash ? null }:

assert sscConfigHash != null -> sscConfigHash != lib.fakeHash;

let
  sscConfig = requireFile {
    name = "liuqin-ssc-config.tar.zst";
    # Extracted from the stock ROM's vendor partition:
    # super -> vendor/etc/sensors/config.  The same files sit in the
    # downstream v0.1.0 release's rootfs volumes, which ship as three ~2 GB
    # tarball parts, so they are registered by hand instead of fetched.
    # Record the sha256 via
    # hardware.liuqin.sensors.sscConfigHash in the NixOS configuration.
    hash =
      if sscConfigHash == null then
        # Leave the derivation valid but unusable: requireFile's own error
        # message carries the operator instructions, and the NixOS module
        # raises the clear assertion before this is ever evaluated.
        lib.fakeHash
      else
        sscConfigHash;
    message = ''
      liuqin-ssc-config.tar.zst is the stock ROM's vendor/etc/sensors/config
      directory, archived deterministically. Extract it from your own device
      dump, place the archive in the Nix store with `nix-store --add-fixed
      sha256 liuqin-ssc-config.tar.zst`, and set
      hardware.liuqin.sensors.sscConfigHash accordingly.
    '';
  };
in
runCommand "liuqin-ssc-config" { } ''
  mkdir -p $out/share/qcom/sm8450/Xiaomi/liuqin/sensors
  tar --zstd -xf ${sscConfig} -C $out/share/qcom/sm8450/Xiaomi/liuqin/sensors
  test -d $out/share/qcom/sm8450/Xiaomi/liuqin/sensors/config
''
