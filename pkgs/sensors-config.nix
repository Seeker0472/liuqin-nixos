# SPDX-License-Identifier: MIT (this expression; see NOTICE for payloads)
#
# The SSC sensor configuration set hexagonrpcd serves to the SLPI
# (/usr/share/qcom/sm8450/Xiaomi/liuqin). The payloads are Qualcomm/Xiaomi
# proprietary binaries extracted from the stock ROM and are NOT
# redistributable by this repository, so this is a fixed-output derivation
# the operator materializes from their own device dump. See docs/PORTING-NOTES.md.
{ lib, runCommand, requireFile }:

let
  sscConfig = requireFile {
    name = "liuqin-ssc-config.tar.zst";
    # PLACEHOLDER: produce from the stock ROM's
    # vendor/etc/sensors/config (see docs/PORTING-NOTES.md) and record the hash.
    hash = lib.fakeHash;
    message = ''
      liuqin-ssc-config.tar.zst is the stock ROM's vendor/etc/sensors/config
      directory, archived deterministically. Extract it from your own device
      dump, place the archive in the Nix store with `nix-store --add-fixed
      sha256 liuqin-ssc-config.tar.zst`, and record its hash in
      pkgs/sensors-config.nix.
    '';
  };
in
runCommand "liuqin-ssc-config" { } ''
  mkdir -p $out/share/qcom/sm8450/Xiaomi/liuqin/sensors
  tar --zstd -xf ${sscConfig} -C $out/share/qcom/sm8450/Xiaomi/liuqin/sensors
  test -d $out/share/qcom/sm8450/Xiaomi/liuqin/sensors/config
''
