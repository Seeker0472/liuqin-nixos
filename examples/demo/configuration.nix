# SPDX-License-Identifier: MIT
#
# The demo machine: Xiaomi Pad 6 Pro (liuqin), GNOME desktop on the dual-boot
# layout - Android keeps boot_a and userdata, NixOS owns the `linux` partition
# and the validated U-Boot path starts it. Persistent boot_b installation is a
# separate, explicitly deferred hardware step.
#
# This is a normal NixOS module and the only file to edit to make it yours:
# the equivalent configuration shipped inside the BSP is config/demo.nix, and
# the two are deliberately separate copies (a self-contained consumer here, the
# BSP's own example configuration there). Change one, change the other - the flake
# check that would catch drift does not exist yet:
# hostname, users, timezone, storage layout, desktop. Everything device-specific
# (kernel, firmware, touch/audio/Wi-Fi/sensor plumbing, the initrd storage
# guard, GNOME policy) is injected by liuqin-nixos.
#
# Scope: this is the "everything the downstream community port has" target -
# GNOME, touch (including the magnetic keyboard cover), rotation, audio,
# Bluetooth, Wi-Fi and the SSC sensor stack - not a hardened system. See the
# BSP README for what the hardware does not support (microphones, cameras,
# USB 3.x OTG, fast charging, automatic brightness).
{ ... }:  # a plain module: the arguments are not needed here

{
  hardware.liuqin = {
    enable = true;
    desktop.gnome.enable = true;

    # The validated U-Boot path loads /boot/{Image,initrd.img,liuqin.dtb} from
    # the `linux` partition, with the kernel command line baked into the DTB.
    boot.loader = "uboot";
    storage.layout = "linux-partition";

    # SSC sensor registry/config from this unit's own stock dump, vendored in
    # the BSP at data/liuqin-ssc-config.tar.zst. A different unit must
    # re-derive it; see the BSP's docs/PORTING-NOTES.md.
    sensors.sscConfigHash = "sha256-9IzksIEZq8NveGBaD5cBSgzNLCh7KmvdjKnEaubCOdU=";
  };

  networking.hostName = "liuqin";
  networking.networkmanager.enable = true;
  time.timeZone = "Asia/Shanghai";

  # GDM signs the demo user in without a prompt. The password is a placeholder:
  # set a real one before using this on a network you do not control.
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

  # Wi-Fi SSH is the supported debug channel (this tablet has no UART). Enroll
  # authorizedKeys below before relying on it: the demo password is refused by
  # SSH anyway.
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  zramSwap.enable = true;

  system.stateVersion = "26.11";
}
