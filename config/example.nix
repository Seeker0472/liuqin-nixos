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

    sensors = {
      # data/liuqin-ssc-config.tar.zst (stock ROM vendor/etc/sensors/config,
      # pinned; add via `nix-store --add-fixed sha256` on other machines).
      sscConfigHash = "sha256-9IzksIEZq8NveGBaD5cBSgzNLCh7KmvdjKnEaubCOdU=";
    };
  };

  networking.hostName = "liuqin";
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Shanghai";

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "input" ];
    initialPassword = "nixos";
  };

  services.openssh = {
    enable = true;
    # Tablet on Wi-Fi: no password auth; enroll authorizedKeys first.
    settings.PasswordAuthentication = false;
  };

  # Matches the nixpkgs 26.11 series this flake pins (nixos-unstable).
  system.stateVersion = "26.11";
}
