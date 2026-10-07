# SPDX-License-Identifier: MIT
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin;
in
{
  config = lib.mkIf cfg.enable {
    # --- Audio: UCM2 for the audioreach card ------------------------------
    # alsa-lib resolves its UCM2 tree through $out/share/alsa/ucm2, a symlink to
    # the alsa-ucm-conf store path, and honours ALSA_CONFIG_UCM2 as an
    # override.  The device files therefore live in liuqinAlsaUcm - a leaf copy
    # of the upstream tree plus the two liuqin files (pkgs/alsa-ucm/default.nix) -
    # rather than in a patched alsa-ucm-conf, which would change alsa-lib and
    # rebuild every audio consumer in the closure.  The user units get the
    # variable explicitly because a lingering systemd --user session does not
    # necessarily inherit the pam_env session environment.
    environment.variables.ALSA_CONFIG_UCM2 = "${pkgs.liuqinAlsaUcm}/share/alsa/ucm2";
    systemd.user.services.pipewire.environment.ALSA_CONFIG_UCM2 =
      "${pkgs.liuqinAlsaUcm}/share/alsa/ucm2";
    systemd.user.services.wireplumber.environment.ALSA_CONFIG_UCM2 =
      "${pkgs.liuqinAlsaUcm}/share/alsa/ucm2";
  };
}
