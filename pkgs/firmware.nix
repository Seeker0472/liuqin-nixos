# SPDX-License-Identifier: MIT (expression; payloads are proprietary)
#
# liuqin firmware tree. The payloads are extracted from the downstream
# project's v0.1.0 release boot.img ramdisk (which in turn came from the
# operator's stock ROM plus pinned linux-firmware); none of it is
# redistributable by this repository, hence requireFile. Produce the
# archives once with the commands in docs/PORTING-NOTES.md, place them in
# the Nix store via `nix-store --add-fixed sha256 <file>` (or
# `nix-prefetch-file`), then the fixed hashes below pin them.
{ lib, runCommand, requireFile, zstd }:

let
  touch = requireFile {
    name = "liuqin-firmware-touch.tar.zst";
    hash = "sha256-wem0/IC4ILwed6H7NcRcNBtFqiVxSJZfL0bMrfQ76Xs=";
    message = "novatek_nt36532_m81_fw_{csot,tm}.bin (from the downstream release ramdisk).";
  };
  dsp = requireFile {
    name = "liuqin-firmware-dsp.tar.zst";
    hash = "sha256-0c167XxGtCUOvQak1sBXK2SxlphlQZAG3cHBedvH+Ww=";
    message = "qcom/sm8475/liuqin/{adsp,cdsp,slpi}.b*/.mbn set (from the downstream release ramdisk).";
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

  # Audio topology: the sound card requests qcom/sm8450/<CardLongName>-tplg.bin.
  mkdir -p $fw/qcom/sm8450
  tar --zstd -xf ${topology} -C $fw/qcom/sm8450

  # Assert the contract paths the kernel actually requests.
  for required in \
    novatek/liuqin/novatek_nt36532_m81_fw_csot.bin \
    qcom/sm8475/liuqin/adsp.mbn \
    qcom/sm8475/liuqin/cdsp.mbn \
    qcom/sm8475/liuqin/slpi.mbn \
    qcom/sm8475/liuqin/a730_zap.mbn \
    qcom/a730_sqe.fw \
    qcom/sm8450/Xiaomi-Pad-6-Pro-tplg.bin; do
    test -r "$fw/$required" || { echo "firmware missing: $required" >&2; exit 1; }
  done
''
