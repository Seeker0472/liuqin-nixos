# SPDX-License-Identifier: MIT
#
# Minimal usable GNOME desktop for Xiaomi Pad 6 Pro (liuqin).
{ config, lib, pkgs, ... }:

{
  hardware.liuqin = {
    enable = true;
    debugTransport = "ssh";
    desktop.gnome.enable = true;
    # Verbose boot diagnostics; keep off unless bring-up needs it.
    boot.debug = false;
    # Camera bring-up tooling (v4l-utils, i2c-tools, liuqin-camtest).  Off by
    # default like the other debug channels: it is a bench tool, not a runtime
    # dependency.  Enable it while working through
    # docs/TODO/CAMERA-MAINLINE.md:
    #   cameraDebug.enable = true;

    sensors = {
      # Operator-supplied stock ROM vendor/etc/sensors/config archive. No
      # proprietary SSC archive is committed; derive this hash locally with
      # `nix hash file --type sha256 --base64` after registering the archive.
      sscConfigHash = "sha256-9IzksIEZq8NveGBaD5cBSgzNLCh7KmvdjKnEaubCOdU=";
    };
  };

  networking.hostName = "liuqin";
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Shanghai";

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "input" ];
    # Console-only bootstrap password: change it right after first login
    # (`passwd`). SSH uses the liuqin deployment key below; password
    # authentication is disabled below.
    initialPassword = "nixos";
    openssh.authorizedKeys.keys = [
      # /home/seeker/.ssh/id_liuqin.pub
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEmzXtiVemck1Ox+0QAL59sntUP4EULCZdHif4oDo7IX seeker@liuqin"
    ];
  };

  services.openssh = {
    # Tablet on Wi-Fi: no password auth; use the liuqin deployment key above.
    settings.PasswordAuthentication = false;
  };

  # Matches the nixpkgs 26.11 series this flake pins (nixos-unstable).
  system.stateVersion = "26.11";
}
