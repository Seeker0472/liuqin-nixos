# SPDX-License-Identifier: MIT (expression; payloads are proprietary)
#
# liuqin firmware tree.
#
# The bulk of the tree comes out of the downstream project's v0.3.1 release:
# its boot.img ramdisk carries the 196 files under lib/firmware that this port
# pins.  It is an operator input, not a fetch - the payload is not
# redistributable and a single release asset is a single point of failure, so
# the derivation only consumes the bytes (`requireFile`, or
# hardware.liuqin.firmware.bootImg) and any mirror of the same file works
# unchanged.  boot.img and installer.img carry the same tree, so only boot.img
# is needed.  v0.3.1 differs from v0.1.0 in exactly one file, the AudioReach
# topology qcom/sm8450/Xiaomi-Pad-6-Pro-tplg.bin: v0.1.0 carries the speaker
# playback graph only, v0.3.1 adds the capture chain (MultiMedia2 Capture ->
# TX_CODEC_DMA_TX_3) the UCM Mic device enables.  The final derivation asserts
# that blob's sha256.
#
# Two more payloads have no public source at all and are operator inputs too:
# the VPU image (from the official MIUI V14 extraction under
# liuqin-mainline-blobs/extracted) and the CS35L41 vendor payloads.
#
# None of the payloads are redistributable by this repository: everything is
# requireFile or a path the machine configuration provides, and nothing is
# committed.
{ cpio
, gzip
, mkbootimg
, python3
, requireFile
, runCommand
, wireless-regdb
, zstd
# Per-operator payloads (a zstd tar archive each): point these at your own
# stock-ROM extraction instead of registering a hash-pinned archive in the
# store. See hardware.liuqin.firmware in modules/liuqin/firmware.nix.
, vpu ? null
, cs35l41 ? null
# The downstream release image whose ramdisk carries the firmware tree. A path
# here overrides the requireFile fallback; see hardware.liuqin.firmware.bootImg.
, releaseBootImg ? null
}:

let
  vpuArchive =
    if vpu != null then
      vpu
    else
      requireFile {
        name = "liuqin-firmware-vpu.tar.zst";
        hash = "sha256-UJ0voVU4dM3A2wH7M83A0lE6EaC9X9Xl0gibI3woYf4=";
        message = ''
          qcom/vpu/vpu20_4v.mbn iris2 VPU firmware, packed as a zstd tar archive
          from the official MIUI V14 extraction in liuqin-mainline-blobs/extracted
          (the downstream release does not carry it).  Register it with
          `nix-store --add-fixed sha256 liuqin-firmware-vpu.tar.zst` - or point
          hardware.liuqin.firmware.vpu at the file and skip that step.
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
  cs35l41Archive =
    if cs35l41 != null then
      cs35l41
    else
      requireFile {
        name = "liuqin-firmware-cs35l41.tar.zst";
        hash = "sha256-D4DMG4r0aY+eIh0F+Wix/Js5nQNhaA63rVtUOr9umxw=";
        message = ''
          CS35L41 Halo protection/calibration payloads from this device's stock
          vendor partition, packed as a zstd tar archive rooted at `cirrus/`.
          Register it with
          `nix-store --add-fixed sha256 liuqin-firmware-cs35l41.tar.zst` - or
          point hardware.liuqin.firmware.cs35l41 at the file.
        '';
      };

  releaseBootImgFile =
    if releaseBootImg != null then
      releaseBootImg
    else
      requireFile {
        name = "boot.img";
        hash = "sha256-llqA7RAZac8Tnesza5bTqwpxwxAgc40NbFwtSCgyVOI=";
        message = ''
          boot.img from the downstream project's v0.3.1 release
          (github.com/yzddmr6/xiaomipad-6pro-mainline/releases/tag/v0.3.1),
          whose ramdisk carries the 196-file firmware tree this port pins. The
          hash is that file's own sha256, so any mirror of the same bytes
          works. Keep a copy named boot.img and register it with
          `nix-store --add-fixed sha256 boot.img` (or
          `nix store add-file --name boot.img <file>`), or point
          hardware.liuqin.firmware.bootImg at the file directly.
          Note: the boot.img in a v0.1.0 release dump is a different image and
          does not satisfy this pin (v0.1.0 predates the AudioReach capture
          topology assertion the tree is checked against).
        '';
      };

  # Unpack just the firmware tree out of that boot image's ramdisk.
  releaseFirmware = runCommand "liuqin-release-firmware" {
    nativeBuildInputs = [ cpio gzip mkbootimg python3 ];
  } ''
    python3 ${mkbootimg}/bin/unpack_bootimg.py \
      --boot_img ${releaseBootImgFile} --out unpacked

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

  # VPU: the iris driver (0006-liuqin-media-iris.patch) requests qcom/vpu/vpu20_4v.mbn, which
  # the release's firmware tree does not carry.
  tar --zstd -xf ${vpuArchive} -C $fw

  # CS35L41: the vendor's Halo wmfw + per-position protection/calibration
  # payloads (see the cs35l41Archive binding above).
  tar --zstd -xf ${cs35l41Archive} -C $fw

  # Bluetooth: mainline's QCA UART driver asks for the "wcn"-prefixed
  # rampatch/NVM names first for the WCN6855 and falls back to the plain ones
  # only when those are missing (drivers/bluetooth/btqca.c: "the mapping
  # between the chip and its corresponding firmware has now been corrected";
  # the unit's dmesg showed qca/wcnhpbtfw21.tlv failing with -2 before
  # qca/hpbtfw21.tlv was taken).
  # Upstream linux-firmware ships the prefixed set, so without these copies the
  # linux-firmware build wins in every loader view that sees both trees and the
  # stock payloads pinned here never run - measured on the unit: the controller
  # reported BTFW.HSP.2.1.0-00660-USB_UART_PATCHZ-6 (linux-firmware) after
  # switch_root while this tree and the unit's bluetooth_a partition carry
  # BTFW.HSP.2.1.0-00570-PATCHZ-1.  Hard links, so no payload is duplicated.
  for f in "$fw"/qca/hp*; do
    ln "$f" "$fw/qca/wcn$(basename "$f")"
  done

  # regulatory.db is packaged separately from linux-firmware in current
  # nixpkgs; it is redistributable, so prefer nixpkgs' copy over the one in
  # the release's tree.
  install -Dm0644 ${wireless-regdb}/lib/firmware/regulatory.db $fw/regulatory.db
  install -Dm0644 ${wireless-regdb}/lib/firmware/regulatory.db.p7s $fw/regulatory.db.p7s

  # WLAN: boot the vendor ath11k set, not the release's compressed one.  The
  # firmware loader expands "updates/" only under its hardcoded
  # /lib/firmware* entries (drivers/base/firmware_loader/main.c, fw_path[]),
  # and the custom firmware_class.path that liuqin-firmware-path installs has
  # no such sibling - so without the copies below the loader's plain sweep
  # finds no amss/board-2/m3/regdb at the requested paths, falls back to the
  # compressed ath11k/WCN6855/hw2.x/*.zst set, and the 5 GHz link then cannot
  # see APs the vendor set hears at -64..-78 dBm (measured 2026-10-07; ch161
  # ran -86..-88 dBm with 50 % loss there, against -48 dBm / 0 % loss under
  # this vendor set).  The four files must stay a set: the vendor board-2
  # with a compressed-set amss dies in `qmi failed to load bdf file` ->
  # `firmware crashed: MHI_CB_EE_RDDM`.  See docs/PORTING-NOTES.md,
  # TODO(ath11k-fw-shadowed).
  for hw in hw2.0 hw2.1; do
    for f in amss.bin board-2.bin m3.bin regdb.bin; do
      install -Dm0644 "$fw/updates/ath11k/WCN6855/$hw/$f" \
                      "$fw/ath11k/WCN6855/$hw/$f"
    done
  done

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
    ath11k/WCN6855/hw2.0/amss.bin \
    ath11k/WCN6855/hw2.1/amss.bin \
    ath11k/WCN6855/hw2.1/board-2.bin \
    ath11k/WCN6855/hw2.1/m3.bin \
    ath11k/WCN6855/hw2.1/regdb.bin \
    updates/ath11k/WCN6855/hw2.0/amss.bin \
    updates/ath11k/WCN6855/hw2.1/amss.bin \
    qcom/vpu/vpu20_4v.mbn \
    qcom/sm8450/Xiaomi-Pad-6-Pro-tplg.bin \
    cirrus/cs35l41-dsp1-spk-prot.wmfw \
    cirrus/cs35l41-dsp1-spk-prot-10251826.wmfw \
    cirrus/cs35l41-dsp1-spk-prot-10251826.bin \
    qca/wcnhpbtfw21.tlv \
    qca/wcnhpnv21g.bin \
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
