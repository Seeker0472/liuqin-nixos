# SPDX-License-Identifier: MIT
#
# Complete demo configuration for liuqin: the "everything the downstream port
# has" target of this repository - GNOME desktop, touch (also with the magnetic
# keyboard cover), rotation, audio, Bluetooth, Wi-Fi and the SSC sensor stack -
# on the dual-boot layout, where Android keeps boot_a and userdata and NixOS
# owns the `linux` partition and is started by the validated U-Boot path;
# persistent boot_b installation remains a separate hardware step.
#
# examples/demo/ is the same system expressed as a *consumer* flake (the
# template to copy for your own machine); this file is the BSP's own smoke
# configuration. They are separate copies on purpose: keep them in sync.
#
# This file is *an example*, not a site configuration: apart from the storage
# layout it inherits nothing machine-specific. Copy it into your own flake (see
# README, "Use from your own flake") and change users, hostname and timezone
# there - config/example.nix is the same thing in minimal form.
{ ... }:

{
  hardware.liuqin = {
    enable = true;
    desktop.gnome.enable = true;

    # The U-Boot chain: /boot/{Image,initrd.img,liuqin.dtb} live on the `linux`
    # partition and carry the command line inside the DTB, so one
    # `install.py --target linux` writing the rootfs image also installs
    # everything the bootloader reads.
    boot.loader = "uboot";
    storage.layout = "linux-partition";

    # SSC sensor registry/config payload from this unit's own stock dump
    # (data/liuqin-ssc-config.tar.zst). Other units must re-derive it; see
    # docs/PORTING-NOTES.md.
    sensors.sscConfigHash = "sha256-9IzksIEZq8NveGBaD5cBSgzNLCh7KmvdjKnEaubCOdU=";
  };

  networking.hostName = "liuqin";
  networking.networkmanager.enable = true;
  time.timeZone = "Asia/Shanghai";

  # Demo login: GDM signs the demo user in without a prompt. The password below
  # is a placeholder - set a real one before putting this on a shared network,
  # and note that SSH refuses it either way (PasswordAuthentication is off).
  services.displayManager.autoLogin = {
    enable = true;
    user = "demo";
  };
  users.users.demo = {
    isNormalUser = true;
    description = "liuqin demo user";
    extraGroups = [ "wheel" "networkmanager" "video" "input" "audio" ];
    initialPassword = "demo";
  };

  # Audio: PipeWire is what GNOME's mixer drives here. The module already ships
  # the device's UCM2 files and audio topology payload, which is what the
  # downstream port's device/audio-topology layer does.
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # Remote access over Wi-Fi is the supported debug channel on this tablet (no
  # UART): enroll authorizedKeys for the demo user first, then `ssh demo@liuqin`.
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # 8-12 GiB of RAM and a GNOME session: swap keeps a browser session alive.
  zramSwap.enable = true;

  system.stateVersion = "26.11";
}
