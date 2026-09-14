# SPDX-License-Identifier: MIT (expression; payloads are proprietary)
#
# liuqin firmware tree. The device firmware (touchscreen panel/CSOT and TM
# variants, WLAN board data, BT rampatch/NVM, GPU zap, DSP images, VPU,
# speaker topology) is extracted from the operator's own stock ROM and the
# pinned upstream linux-firmware pieces; none of it is redistributable by
# this repository, hence requireFile.
#
# Fill the hashes after producing the archives once; the layout contract the
# kernel expects is documented in docs/PORTING-NOTES.md.
{ lib, runCommand, requireFile, zstd }:

let
  touch = requireFile {
    name = "liuqin-firmware-touch.tar.zst";
    hash = lib.fakeHash;
    message = "novatek_nt36532_m81_fw_{csot,tm}.bin from the stock vendor firmware.";
  };
  dsp = requireFile {
    name = "liuqin-firmware-dsp.tar.zst";
    hash = lib.fakeHash;
    message = "SM8475 DSP images (adsp.mbn/cdsp.mbn/slpi.mbn sets, 68 files) from NON-HLOS.bin.";
  };
  gpu = requireFile {
    name = "liuqin-firmware-gpu.tar.zst";
    hash = lib.fakeHash;
    message = "a730_zap.mbn, a730_sqe.fw, gmu_gen70000.bin from the stock ROM.";
  };
  bt = requireFile {
    name = "liuqin-firmware-bt.tar.zst";
    hash = lib.fakeHash;
    message = "QCA6490 bt_firmware image set (BTFM.bin constructible names).";
  };
  wlanBoard = requireFile {
    name = "liuqin-firmware-wlan-board.tar.zst";
    hash = lib.fakeHash;
    message = "qca6490/bd_m81.elf board data from the stock firmware_mnt image.";
  };
in
runCommand "liuqin-firmware" { nativeBuildInputs = [ zstd ]; } ''
  fw=$out/lib/firmware
  mkdir -p $fw

  # Touchscreen: the DTS requests novatek/liuqin/<name> early in probe.
  mkdir -p $fw/novatek/liuqin
  tar --zstd -xf ${touch} -C $fw/novatek/liuqin

  # DSP remoteprocs (qcom_q6v5_pas): qcom/sm8475/liuqin/{adsp,cdsp,slpi}.mbn
  mkdir -p $fw/qcom/sm8475/liuqin
  tar --zstd -xf ${dsp} -C $fw/qcom/sm8475/liuqin

  # GPU.
  tar --zstd -xf ${gpu} -C $fw
  install -Dm0644 $fw/a730_zap.mbn $fw/qcom/sm8475/liuqin/a730_zap.mbn 2>/dev/null || true

  # Bluetooth.
  mkdir -p $fw/qca
  tar --zstd -xf ${bt} -C $fw

  # WLAN board data at the ath11k request paths.
  mkdir -p $fw/ath11k/WCN6855/hw2.0 $fw/ath11k/WCN6855/hw2.1
  tar --zstd -xf ${wlanBoard} -C $fw
''

# NOTE: exact install paths mirror tools/build-liuqin-firmware-prep.sh of the
# downstream project; keep in sync with the kernel DTS firmware-name strings
# (patches/kernel/0001): adsp/cdsp/slpi under qcom/sm8475/liuqin, GPU zap at
# qcom/sm8475/liuqin/a730_zap.mbn, touch at novatek/liuqin/, topology at
# qcom/sm8450/Xiaomi-Pad-6-Pro-tplg.bin.
