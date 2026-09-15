# SPDX-License-Identifier: MIT (expression; payloads are proprietary)
#
# liuqin firmware tree. The payloads are extracted from the downstream
# project's v0.1.0 release boot.img ramdisk (which in turn came from the
# operator's stock ROM plus pinned linux-firmware); none of it is
# redistributable by this repository, hence requireFile. Produce the
# archives once with the commands in docs/PORTING-NOTES.md, place them in
# the Nix store via `nix-store --add-fixed sha256 <file>` (or
# `nix-prefetch-file`), then the fixed hashes below pin them.
{ lib, runCommand, requireFile, zstd, linux-firmware }:

let
  touch = requireFile {
    name = "liuqin-firmware-touch.tar.zst";
    hash = "sha256-wem0/IC4ILwed6H7NcRcNBtFqiVxSJZfL0bMrfQ76Xs=";
    message = "novatek_nt36532_m81_fw_{csot,tm}.bin (from the downstream release ramdisk).";
  };
  dsp = requireFile {
    name = "liuqin-firmware-dsp.tar.zst";
    hash = "sha256-0c167XxGtCUOvQak1sBXK2SxlphlQZAG3cHBedvH+Ww=";
    message = ''
      liuqin-firmware-dsp.tar.zst is an operator-supplied fixed-output input:
      pack the qcom/sm8475/liuqin/{adsp,cdsp,slpi}.b*/.mbn DSP firmware set
      (from the downstream release ramdisk or your own stock ROM dump) into a
      zstd tar archive, then register it with
      `nix-store --add-fixed sha256 liuqin-firmware-dsp.tar.zst`.
      See docs/PORTING-NOTES.md for the exact archive layout.
    '';
  };
  gpu = requireFile {
    name = "liuqin-firmware-gpu.tar.zst";
    hash = "sha256-6hfpXUe4o3BgNvaGdBA6NuLHacEguVTtYA1Z09Z80c0=";
    message = "a730_zap.mbn, a730_sqe.fw, gmu_gen70000.bin (from the downstream release ramdisk).";
  };
  bt = requireFile {
    name = "liuqin-firmware-bt.tar.zst";
    hash = "sha256-g77Vk/9eZ3KjUXdCvCHm3Xb6Qo79laRlB1LqVBbxlp4=";
    message = "qca/hpnv21* and hpbtfw21.tlv QCA6490 set (from the downstream release ramdisk).";
  };
  wlanBoard = requireFile {
    name = "liuqin-firmware-wlan-board.tar.zst";
    hash = "sha256-rKrzSMo2k0VLuC5m8dXN99IFHT6hab4m9h8s2HV6yvs=";
    message = "ath11k/WCN6855 hw2.0/hw2.1 board data + updates/ tuples (from the downstream release ramdisk).";
  };
  vpu = requireFile {
    name = "liuqin-firmware-vpu.tar.zst";
    hash = "sha256-UJ0voVU4dM3A2wH7M83A0lE6EaC9X9Xl0gibI3woYf4=";
    message = ''
      qcom/vpu/vpu20_4v.mbn iris2 VPU firmware, packed as a zstd tar
      archive. The pinned hash field above is the sha256 of this
      liuqin-firmware-vpu.tar.zst archive; the downstream project instead
      pins the blob-level sha256 3567fd45 (OS2.0.6.0 copy), while this
      archive carries the blob from liuqin-mainline-blobs/extracted whose
      blob-level sha256 is cc27f8e3 (provenance only, not what requireFile
      checks).
    '';
  };
  topology = requireFile {
    name = "liuqin-firmware-topology.tar.zst";
    hash = "sha256-5r17TJ4Qc6KS7gcpMD+4wvqwLd5bNb6cXoWNavTm03k=";
    message = "qcom/sm8450/Xiaomi-Pad-6-Pro-tplg.bin audio topology (from the downstream release ramdisk).";
  };
in
runCommand "liuqin-firmware" { nativeBuildInputs = [ zstd ]; } ''
  fw=$out/lib/firmware
  mkdir -p $fw

  # Touchscreen: the DTS requests novatek/liuqin/<name> early in probe.
  mkdir -p $fw/novatek/liuqin
  tar --zstd -xf ${touch} -C $fw/novatek/liuqin

  # DSP remoteprocs (qcom_q6v5_pas): qcom/sm8475/liuqin/{adsp,cdsp,slpi}.*
  mkdir -p $fw/qcom/sm8475/liuqin
  tar --zstd -xf ${dsp} -C $fw

  # GPU: a6xx driver requests qcom/a730_sqe.fw and qcom/gmu_gen70000.bin
  # (already qcom/-prefixed in the archive); the zap shader goes to the
  # liuqin-specific path.
  mkdir -p $fw/qcom/sm8475/liuqin
  tar --zstd -xf ${gpu} -C $fw
  install -Dm0644 $fw/qcom/a730_zap.mbn $fw/qcom/sm8475/liuqin/a730_zap.mbn

  # Bluetooth: qca/ tree as-is.
  tar --zstd -xf ${bt} -C $fw

  # WLAN: ath11k/ plus the updates/ preference tuples.
  tar --zstd -xf ${wlanBoard} -C $fw

  # VPU: the iris driver (patch 0007) requests qcom/vpu/vpu20_4v.mbn.
  tar --zstd -xf ${vpu} -C $fw

  # Audio topology: the sound card requests qcom/sm8450/<CardLongName>-tplg.bin.
  mkdir -p $fw/qcom/sm8450
  tar --zstd -xf ${topology} -C $fw/qcom/sm8450

  # regulatory.db comes from nixpkgs linux-firmware (redistributable), not
  # from the device dump.
  install -Dm0644 ${linux-firmware}/lib/firmware/regulatory.db $fw/regulatory.db
  install -Dm0644 ${linux-firmware}/lib/firmware/regulatory.db.p7s $fw/regulatory.db.p7s

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
