# SPDX-License-Identifier: MIT
#
# Minimal usable GNOME desktop for Xiaomi Pad 6 Pro (liuqin).
{ config, lib, pkgs, ... }:

{
  hardware.liuqin = {
    enable = true;
    desktop.gnome.enable = true;
    # Verbose boot diagnostics; keep off unless bring-up needs it.
    boot.debug = false;
  };

  networking.hostName = "liuqin";
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Shanghai";

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "input" ];
    initialPassword = "nixos";
  };

  services.openssh.enable = true;

  system.stateVersion = "26.05";
}
