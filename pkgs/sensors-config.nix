# SPDX-License-Identifier: MIT (this expression; see NOTICE for payloads)
#
# The SSC sensor configuration set hexagonrpcd serves to the SLPI
# (/usr/share/qcom/sm8450/Xiaomi/liuqin). The payloads are Qualcomm/Xiaomi
# proprietary binaries extracted from the stock ROM and are NOT
# redistributable by this repository, so this is a fixed-output derivation
# the operator materializes from their own device dump. See docs/PORTING-NOTES.md.
{ lib, runCommand, requireFile, zstd, sscConfigHash ? null }:

assert sscConfigHash != null -> sscConfigHash != lib.fakeHash;

let
  # These two files are plain-text parts of the stock SSC contract. Keeping a
  # fallback makes older operator archives (which contained only
  # vendor/etc/sensors/config) usable while still validating the exact ROM
  # property names consumed by the patched hexagonrpc registry shim.
  stockSnsRegConfig = builtins.toFile "liuqin-sns-reg-config" ''
    version=8
    file=hw_platform=/sys/devices/soc0/hw_platform
    file=platform_subtype=/sys/devices/soc0/platform_subtype
    file=platform_subtype_id=/sys/devices/soc0/platform_subtype_id
    file=platform_version=/sys/devices/soc0/platform_version
    file=soc_id=/sys/devices/soc0/soc_id
    file=revision=/sys/devices/soc0/revision
    file=output=/mnt/vendor/persist/sensors/registry/registry
    property=persist.vendor.sensors.enable.property=/mnt/vendor/persist/sensors/registry/file1
    property=persist.vendor.sensors.enable.property1=/mnt/vendor/persist/sensors/registry/file2
  '';
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
      directory, optionally accompanied by sns_reg.conf and sns_reg_version,
      archived deterministically. Extract it from your own device dump, place
      the archive in the Nix store with `nix-store --add-fixed sha256
      liuqin-ssc-config.tar.zst`, and set hardware.liuqin.sensors.sscConfigHash
      accordingly. Config-only archives are accepted; the audited plain-text
      registry contract is synthesized for them.
    '';
  };
in
runCommand "liuqin-ssc-config" { nativeBuildInputs = [ zstd ]; } ''
  set -eu
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  mkdir -p $out/share/qcom/sm8450/Xiaomi/liuqin/sensors
  mkdir -p $out/share/qcom/sm8450/Xiaomi/liuqin/socinfo
  tar --zstd -xf ${sscConfig} -C "$work"
  test -d "$work/config"
  cp -a "$work/config" $out/share/qcom/sm8450/Xiaomi/liuqin/sensors/

  # hexagonrpcd maps these paths into the virtual Android filesystem. Accept
  # either spelling from an operator archive and otherwise synthesize the
  # known stock text contract. The virtual hexagonrpc filesystem exposes the
  # installed file as sns_reg.conf; sns_reg_config is accepted only as an
  # input archive compatibility spelling.
  reg_config=
  if [ -f "$work/sns_reg.conf" ] && [ -f "$work/sns_reg_config" ]; then
    cmp -s "$work/sns_reg.conf" "$work/sns_reg_config" || {
      echo 'conflicting sns_reg.conf and sns_reg_config inputs' >&2
      exit 1
    }
  fi
  for candidate in "$work/sns_reg.conf" "$work/sns_reg_config"; do
    if [ -f "$candidate" ]; then
      reg_config=$candidate
      break
    fi
  done
  if [ -z "$reg_config" ]; then
    reg_config=${stockSnsRegConfig}
  fi
  install -Dm0644 "$reg_config" \
    $out/share/qcom/sm8450/Xiaomi/liuqin/sensors/sns_reg.conf
  reg_version=$(sed -n 's/^version=//p' \
    $out/share/qcom/sm8450/Xiaomi/liuqin/sensors/sns_reg.conf)
  [ "$reg_version" = 8 ] || {
    echo "unsupported sns_reg.conf version: $reg_version" >&2
    exit 1
  }
  grep -Fqx 'property=persist.vendor.sensors.enable.property=/mnt/vendor/persist/sensors/registry/file1' \
    $out/share/qcom/sm8450/Xiaomi/liuqin/sensors/sns_reg.conf
  grep -Fqx 'property=persist.vendor.sensors.enable.property1=/mnt/vendor/persist/sensors/registry/file2' \
    $out/share/qcom/sm8450/Xiaomi/liuqin/sensors/sns_reg.conf

  # The firmware opens the version through the registry directory's parent;
  # it is a NUL-terminated file, not a newline-terminated text file. The
  # current V14 image has version 12 while its sns_reg.conf header is
  # version 8. Validate that an archive's sibling is this exact record, or
  # synthesize the same record for older config-only archives.
  printf 'version=12\0' > "$work/expected-sns-reg-version"
  if [ -f "$work/sns_reg_version" ]; then
    cmp -s "$work/sns_reg_version" "$work/expected-sns-reg-version" || {
      echo 'sns_reg_version is not the audited version=12 NUL record' >&2
      exit 1
    }
  fi
  install -Dm0644 "$work/expected-sns-reg-version" \
    $out/share/qcom/sm8450/Xiaomi/liuqin/sensors/sns_reg_version
  version_bytes=$(wc -c < \
    $out/share/qcom/sm8450/Xiaomi/liuqin/sensors/sns_reg_version)
  [ "$version_bytes" = 11 ]
  ln -s /var/lib/liuqin-sensors/registry \
    $out/share/qcom/sm8450/Xiaomi/liuqin/sensors/registry
  # The FastRPC /persist/sensors/registry mount is writable runtime state;
  # static vendor files above remain immutable in the Nix store.
  ln -s /var/lib/liuqin-sensors \
    $out/share/qcom/sm8450/Xiaomi/liuqin/runtime

  # The SSC registry contract reads these Qualcomm socinfo attributes through
  # /sys/devices/soc0. These values come from the Liuqin stock boot log
  # (socinfo v0.16, id=531, ver=1.0, hw_plat=8, hw_plat_subtype=0,
  # hw_plat_ver=65536); do not substitute a generic SM8450 value here.
  printf 'MTP\n' > \
    $out/share/qcom/sm8450/Xiaomi/liuqin/socinfo/hw_platform
  printf 'Unknown\n' > \
    $out/share/qcom/sm8450/Xiaomi/liuqin/socinfo/platform_subtype
  printf '0\n' > \
    $out/share/qcom/sm8450/Xiaomi/liuqin/socinfo/platform_subtype_id
  printf '65536\n' > \
    $out/share/qcom/sm8450/Xiaomi/liuqin/socinfo/platform_version
  printf '531\n' > \
    $out/share/qcom/sm8450/Xiaomi/liuqin/socinfo/soc_id
  printf '1.0\n' > \
    $out/share/qcom/sm8450/Xiaomi/liuqin/socinfo/revision

  (cd $out/share/qcom/sm8450/Xiaomi/liuqin/sensors/config && \
    find . -maxdepth 1 -type f -printf '%P\0' | LC_ALL=C sort -z | \
    xargs -0 sha256sum) > \
    $out/share/qcom/sm8450/Xiaomi/liuqin/sensors/config.SHA256SUMS
''
