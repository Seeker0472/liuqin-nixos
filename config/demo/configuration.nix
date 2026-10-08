# SPDX-License-Identifier: MIT
#
# The demo machine: Xiaomi Pad 6 Pro (liuqin), GNOME desktop on the dual-boot
# layout - Android keeps boot_a and userdata, NixOS owns the `linux` partition
# and the validated U-Boot path starts it.
#
# This is a normal NixOS module and the only machine file in the repository.
# The BSP builds this very file as its `demo` target (flake.nix,
# nixosConfigurations.demo), so it is exercised by the BSP's own checks and
# there is no second copy to keep in sync.
# `nix flake init -t github:Seeker0472/liuqin-nixos` copies the whole directory.
#
# Scope: the "everything the downstream community port has" target - GNOME,
# touch (including the magnetic keyboard cover), rotation, audio, Bluetooth,
# Wi-Fi, the SSC sensor stack and the camera stack (three sensors through
# libcamera's software ISP) - not a hardened system. See the BSP README for
# what the hardware does not support (microphones, USB 3.x OTG, fast
# charging, automatic brightness).
#
# Per-device data this file cannot carry, all operator-supplied:
#   - the SSC sensor registry archive: point hardware.liuqin.sensors.sscConfig
#     at your own extraction, or register the archive in the store and replace
#     sscConfigHash below with its hash (docs/PORTING-NOTES.md);
#   - the fingerprint trustlet state: fingerprint.enable only makes the stack
#     reachable; creating the credential is a physical procedure
#     (docs/INSTALL.md, Fingerprint);
#   - the MiPPS HMAC keys, read from the persist partition
#     (docs/PORTING-NOTES.md).
{ pkgs, ... }:

{
  hardware.liuqin = {
    enable = true;
    # "both" keeps Wi-Fi SSH while exposing the NCM/ECM USB deploy link.
    debugTransport = "both";
    desktop.gnome.enable = true;
    boot.loader = "uboot";
    storage.layout = "linux-partition";

    camera = {
      # The camera stack: liuqin-camera (media-graph routing + formats),
      # libcamera, and on-demand routing of the wide module.
      enable = true;
      # EXPERIMENTAL: applies the local libcamera AF series; it reaches
      # pipewire and wireplumber, the processes that run libcamera in a GNOME
      # session. See the camera section of the BSP README.
      autofocus.enable = true;
    };

    # OEM FPC1264 stack: the software is in this tree, the firmware, trustlet
    # credentials and RPMB state are per-device data. Without the credential
    # creation it only makes the stack reachable; password login is untouched
    # either way (docs/INSTALL.md, Fingerprint).
    fingerprint.enable = true;

    # MiPPS coordinator: runs because this system carries the key files; the
    # keys themselves come from the persist partition (docs/PORTING-NOTES.md).
    mipps.enable = true;

    sensors = {
      # Operator-supplied stock ROM vendor/etc/sensors/config archive. No
      # proprietary SSC archive is committed; a different unit must register
      # its own archive and re-derive this hash, or leave both this and
      # sscConfig unset to skip the SSC stack (the module warns), see
      # docs/PORTING-NOTES.md.
      sscConfigHash = "sha256-9IzksIEZq8NveGBaD5cBSgzNLCh7KmvdjKnEaubCOdU=";
    };
  };

  # ssh-ng:// deployments (lq-deploy-direct) need the machine user to be
  # trusted by the remote daemon; the legacy ssh:// store did not.
  nix.settings.trusted-users = [ "root" "liuqin" ];

  networking.hostName = "liuqin";
  networking.networkmanager.enable = true;
  time.timeZone = "Asia/Shanghai";

  # GDM signs the user in without a prompt. The password is a placeholder:
  # set a real one before using this on a network you do not control.
  services.displayManager.autoLogin = {
    enable = true;
    user = "liuqin";
  };
  users.users.liuqin = {
    isNormalUser = true;
    description = "liuqin user";
    extraGroups = [ "wheel" "networkmanager" "video" "input" "audio" ];
    initialPassword = "liuqin";
    openssh.authorizedKeys.keys = [
      # /home/seeker/.ssh/id_liuqin.pub
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEmzXtiVemck1Ox+0QAL59sntUP4EULCZdHif4oDo7IX seeker@liuqin"
    ];
  };

  # PipeWire is what GNOME's mixer drives here; the BSP ships this device's
  # UCM2 files and audio topology payloads.
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # Wi-Fi SSH is the supported debug channel (this tablet has no UART). The
  # liuqin deployment key is enrolled above; the account password is refused
  # by SSH anyway.
  services.openssh = {
    settings.PasswordAuthentication = false;
  };

  # Audio tools on the device: alsaucm/arecord/amixer/aplay. The system
  # already carries alsa-lib and the liuqin UCM2 tree; see PORTING-NOTES.md
  # (Audio) for the verified state and the remaining limits.
  environment.systemPackages = [
    pkgs.alsa-utils
    # Flashlight Quick Settings toggle + brightness slider for the rear flash
    # LED (overlay package, see pkgs/gnome-flashlight).
    pkgs.liuqinGnomeFlashlight
  ];

  # Hand the flash LED's brightness attribute to the video group (the camera
  # stack's group): the LED class device has no /dev node, so udev's
  # GROUP/MODE/uaccess have nothing to act on - the attribute itself has to be
  # adjusted from a rule.
  services.udev.extraRules = ''
    SUBSYSTEM=="leds", KERNEL=="white:flash", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/leds/white:flash/brightness", RUN+="${pkgs.coreutils}/bin/chmod 0664 /sys/class/leds/white:flash/brightness"
  '';

  # Enable the flashlight extension for the user; the LED itself is the only
  # state it has, so nothing else needs configuring.
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/shell" = {
        enabled-extensions = [ "liuqin-flashlight@liuqin" ];
      };
    }
  ];

  zramSwap.enable = true;

  system.stateVersion = "26.11";
}
