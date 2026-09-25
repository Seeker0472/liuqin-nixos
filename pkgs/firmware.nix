# SPDX-License-Identifier: MIT (expression; payloads are proprietary)
#
# liuqin firmware tree.
#
# Every payload except the VPU image comes out of the downstream project's
# v0.1.0 release (github.com/yzddmr6/xiaomipad-6pro-mainline): its boot.img
# ramdisk carries the firmware tree that port pins (196 files under
# lib/firmware), and the hash below is the boot.img hash the release's own
# SHA256SUMS lists.  boot.img and installer.img carry the same tree, so only
# boot.img is fetched.  That tree is byte-identical to the archives this
# expression used to require - verified file by file against the touch, DSP,
# GPU, Bluetooth, WLAN-board and audio-topology sets - so the kernel sees the
# same files as before.
#
# TODO: replace the release with a better source as soon as one exists: an
# official Xiaomi image we can fetch, a mirror that outlives a single release,
# or upstream linux-firmware once these blobs land there.  Two payloads have
# no public source at all and stay operator inputs, so they cannot move with
# it: the VPU image (from the official MIUI V14 extraction under
# liuqin-mainline-blobs/extracted) and the SSC sensor config
# (pkgs/sensors-config.nix).
#
# None of the payloads are redistributable by this repository: the release is
# fetched by hash, the operator inputs are requireFile, and neither is
# committed.
{ cpio
, fetchurl
, gzip
, mkbootimg
, python3
, requireFile
, runCommand
, wireless-regdb
, zstd
}:

let
  vpu = requireFile {
    name = "liuqin-firmware-vpu.tar.zst";
    hash = "sha256-UJ0voVU4dM3A2wH7M83A0lE6EaC9X9Xl0gibI3woYf4=";
    message = ''
      qcom/vpu/vpu20_4v.mbn iris2 VPU firmware, packed as a zstd tar archive
      from the official MIUI V14 extraction in liuqin-mainline-blobs/extracted
      (the downstream release does not carry it).  Register it with
      `nix-store --add-fixed sha256 liuqin-firmware-vpu.tar.zst`.
    '';
  };

  releaseBootImg = fetchurl {
    url = "https://github.com/yzddmr6/xiaomipad-6pro-mainline/releases/download/v0.1.0/boot.img";
    hash = "sha256-X59akAjgwTQaLwPnajTe0NGah2lHhvkYUeAdBLnqcTo=";
  };

  # Unpack just the firmware tree out of that boot image's ramdisk.
  releaseFirmware = runCommand "liuqin-release-firmware" {
    nativeBuildInputs = [ cpio gzip mkbootimg python3 ];
  } ''
    python3 ${mkbootimg}/bin/unpack_bootimg.py \
      --boot_img ${releaseBootImg} --out unpacked

    # The ramdisk is a gzip'd cpio archive; the firmware tree is the part of
    # it this repository distributes.
    mkdir ramdisk-root
    ( cd ramdisk-root && gzip -dc ../unpacked/ramdisk | cpio -idm --quiet )
    mkdir -p $out/lib
    cp -a ramdisk-root/lib/firmware $out/lib/firmware
  '';
in
runCommand "liuqin-firmware" { nativeBuildInputs = [ zstd ]; } ''
  fw=$out/lib/firmware
  mkdir -p $fw
  cp -a ${releaseFirmware}/lib/firmware/. $fw/
  # cp -a keeps the store's read-only mode, but the VPU payload below adds a
  # directory of its own (qcom/vpu).
  chmod -R u+w $fw

  # VPU: the iris driver (patch 0007) requests qcom/vpu/vpu20_4v.mbn, which
  # the release's firmware tree does not carry.
  tar --zstd -xf ${vpu} -C $fw

  # regulatory.db is packaged separately from linux-firmware in current
  # nixpkgs; it is redistributable, so prefer nixpkgs' copy over the one in
  # the release's tree.
  install -Dm0644 ${wireless-regdb}/lib/firmware/regulatory.db $fw/regulatory.db
  install -Dm0644 ${wireless-regdb}/lib/firmware/regulatory.db.p7s $fw/regulatory.db.p7s

  # Assert the contract paths the kernel actually requests.
  for required in \
    novatek/liuqin/novatek_nt36532_m81_fw_csot.bin \
    novatek/liuqin/novatek_nt36532_m81_fw_tm.bin \
    qcom/sm8475/liuqin/adsp.mbn \
    qcom/sm8475/liuqin/cdsp.mbn \
    qcom/sm8475/liuqin/slpi.mbn \
    qcom/sm8475/liuqin/a730_zap.mbn \
    qcom/a730_sqe.fw \
    qcom/gmu_gen70000.bin \
    ath11k/WCN6855/hw2.0/amss.bin.zst \
    updates/ath11k/WCN6855/hw2.0/amss.bin \
    updates/ath11k/WCN6855/hw2.1/amss.bin \
    qcom/vpu/vpu20_4v.mbn \
    qcom/sm8450/Xiaomi-Pad-6-Pro-tplg.bin \
    regulatory.db \
    regulatory.db.p7s; do
    test -r "$fw/$required" || { echo "firmware missing: $required" >&2; exit 1; }
  done
''
