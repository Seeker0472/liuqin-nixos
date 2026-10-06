# SPDX-License-Identifier: MIT (expression; payloads are proprietary)
#
# liuqin firmware tree.
#
# Every payload except the VPU image and the CS35L41 archive (below) comes
# out of the downstream project's v0.3.1 release
# (github.com/yzddmr6/xiaomipad-6pro-mainline): its boot.img
# ramdisk carries the firmware tree that port pins (196 files under
# lib/firmware), and the hash below is the boot.img hash the release's own
# SHA256SUMS lists.  boot.img and installer.img carry the same tree, so only
# boot.img is fetched.  v0.3.1 differs from v0.1.0 in exactly one file, the
# AudioReach topology qcom/sm8450/Xiaomi-Pad-6-Pro-tplg.bin: v0.1.0 carries
# the speaker playback graph only, v0.3.1 adds the capture chain
# (MultiMedia2 Capture -> TX_CODEC_DMA_TX_3) the UCM Mic device enables.
# The final derivation asserts that blob's sha256.
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

  # The vendor's CS35L41 speaker DSP payloads, extracted from the stock ROM's
  # vendor partition (`vendor/firmware/` in the super image): the two Halo
  # wmfw files plus the per-position protection and calibration records and
  # the music/voice tuning lists.  They are the set the protection bring-up in
  # patch 0004 was written against; linux-firmware's generic
  # cs35l41-dsp1-spk-prot.wmfw names the same controls but is a different
  # build, and its -10251826 entry points at another SKU's tuning.  The files
  # are installed under the names the mainline driver actually requests
  # (generic and -10251826 suffixed).
  cs35l41 = requireFile {
    name = "liuqin-firmware-cs35l41.tar.zst";
    hash = "sha256-D4DMG4r0aY+eIh0F+Wix/Js5nQNhaA63rVtUOr9umxw=";
    message = ''
      CS35L41 Halo protection/calibration payloads from this device's stock
      vendor partition, packed as a zstd tar archive rooted at `cirrus/`.
      Register it with
      `nix-store --add-fixed sha256 liuqin-firmware-cs35l41.tar.zst`.
    '';
  };

  releaseBootImg = fetchurl {
    url = "https://github.com/yzddmr6/xiaomipad-6pro-mainline/releases/download/v0.3.1/boot.img";
    hash = "sha256-llqA7RAZac8Tnesza5bTqwpxwxAgc40NbFwtSCgyVOI=";
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

  # CS35L41: the vendor's Halo wmfw + per-position protection/calibration
  # payloads (see the cs35l41 requireFile above).
  tar --zstd -xf ${cs35l41} -C $fw

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
    cirrus/cs35l41-dsp1-spk-prot.wmfw \
    cirrus/cs35l41-dsp1-spk-prot-10251826.wmfw \
    cirrus/cs35l41-dsp1-spk-prot-10251826.bin \
    regulatory.db \
    regulatory.db.p7s; do
    test -r "$fw/$required" || { echo "firmware missing: $required" >&2; exit 1; }
  done

  # The capture subgraph is the one payload that differs between the v0.1.0
  # and v0.3.1 trees, and it is the whole reason this pin moved.  Pin the
  # bytes: without this hash a future source swap could silently ship a
  # speaker-only topology again and the UCM Mic device would enable a
  # capture chain that is not there.
  tplg=$fw/qcom/sm8450/Xiaomi-Pad-6-Pro-tplg.bin
  test "$(sha256sum "$tplg" | cut -d' ' -f1)" = \
    9c9f8bfcffde1f52c143d58cba821c5f6b3899553370ab92a88b90d81fef9ee9 || {
    echo "unexpected AudioReach topology: $(sha256sum "$tplg")" >&2
    exit 1
  }
''
