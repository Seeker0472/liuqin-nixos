# SPDX-License-Identifier: MIT
#
# Camera bring-up tooling: the userspace half of the sensor/CAMSS work tracked
# in docs/TODO/CAMERA-MAINLINE.md. It exists because every missing tool costs a
# reboot round on a board whose only console is the panel.
#
#   v4l-utils   media-ctl (topology / link checks) and v4l2-ctl (format
#               negotiation, capture, stream statistics)
#   i2c-tools   i2ctransfer, for explicit register reads over the CCI adapter
#               the sensor driver binds to
#   liuqin-camtest  capture N frames from a video node and print per-frame
#               checksums, plus the topology and format list in one go
#               (pkgs/camtest.nix)
#
# i2cdetect is deliberately not documented as a camera probe: it walks every
# address with SMBus quick writes, which sensors do not expect, and it cannot
# be trusted to distinguish "no device" from "bus not powered". Read the chip
# id through the sensor driver (it logs it on probe) or with an explicit
# i2ctransfer.
#
# Off by default and deliberately never enabled by the BSP, like the USB debug
# shell: nothing in a normal installation consumes these tools, and i2c-tools
# gives root raw write access to the buses the camera rails and sensors sit on.
# Enable it only while doing bring-up (docs/TODO/CAMERA-MAINLINE.md).
#
# TODO(bring-up): delete this module once the camera paths are stable - remove
# the import in modules/liuqin/default.nix, the commented
# `cameraDebug.enable` line in config/example.nix, the helper package
# (pkgs/camtest.nix) and its overlay entry together with it. The conditions
# are written down in docs/TODO/CAMERA-MAINLINE.md, phase 5.
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin.cameraDebug;
in
{
  options.hardware.liuqin.cameraDebug.enable = lib.mkEnableOption ''
    the camera bring-up tooling: v4l-utils (media-ctl, v4l2-ctl), i2c-tools
    (i2ctransfer) and the liuqin-camtest capture/checksum helper'';

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ liuqinCamtest v4l-utils i2c-tools ];
  };
}
