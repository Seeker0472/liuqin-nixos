# The demo target: the example configuration plus the camera stack that needs
# the still upstream-bound libcamera autofocus series (injected into the
# session's libcamera consumers).  See docs/PORTING-NOTES.md (Camera) for the
# hardware facts and open items.
{ lib, config, pkgs, ... }:
{
  imports = [ ../examples/demo/configuration.nix ];

  # ssh-ng:// deployments (lq-deploy-direct) need the demo user to be
  # trusted by the remote daemon; the legacy ssh:// store did not.
  nix.settings.trusted-users = [ "root" "demo" ];

  hardware.liuqin.camera.autofocus.enable = true;

  # Fingerprint (FPC1264): the QSEECOM TEE transport, the power/reset/IRQ
  # control driver (no SPI: the trustlet owns the bus) and the OEM userspace
  # stack.  Firmware and credentials are per-device data; the operator steps
  # are in docs/TODO/FINGERPRINT-MAINLINE.md.
  hardware.liuqin.fingerprint.enable = true;

  # USB bring-up deployment: the single kernel carries every feature
  # (USB3 peripheral, Type-C host/OTG, DP Alt Mode); the MiPPS coordinator
  # runs because this system carries the key files.
  # debugTransport = "both" keeps the Wi-Fi SSH recovery channel while
  # exposing the NCM/ECM gadget for the USB deploy/test link.
  hardware.liuqin.mipps.enable = true;
  hardware.liuqin.debugTransport = lib.mkForce "both";

  # Audio tools on the device: alsaucm/arecord/amixer/aplay.  The system
  # already carries alsa-lib and the liuqin UCM2 tree; see PORTING-NOTES.md
  # (Audio) for the verified state and the remaining limits.
  environment.systemPackages = [ pkgs.alsa-utils ];
}
