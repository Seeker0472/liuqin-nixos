# SPDX-License-Identifier: MIT
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin;
in
{
  config = lib.mkIf cfg.enable {
    # --- Backlight ---------------------------------------------------------
    # systemd-backlight restores whatever the last session left; on a panel
    # whose boot evidence is the backlight itself, force a known-good level
    # once, before the display manager.
    # The panel is dark until this runs and it is the only log channel, so
    # graphical.target is far too late: measured on the first boot this
    # finished at +98 s while the display driver (and the DRM framebuffer) are
    # up within the first second.  systemd-backlight restores whatever the last
    # session left, so this still has to run after it to win.
    # Charger mode skips the unit instead of writing and exiting.
    systemd.services.liuqin-backlight-default = {
      description = "Restore the liuqin normal-desktop backlight default";
      unitConfig.ConditionKernelCommandLine = "!androidboot.mode=charger";
      wantedBy = [ "basic.target" ];
      wants = [ "systemd-backlight@backlight:ktz8866-backlight.service" ];
      after = [ "systemd-backlight@backlight:ktz8866-backlight.service" ];
      before = [ "display-manager.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.liuqinBacklightDefault}/bin/liuqin-backlight-default";
      };
    };

    # --- Panel console repaint --------------------------------------------
    # The installed system relies on patch 0003's one early pipeline cycle.
    # Do not add a late userspace blank/unblank here: after GDM owns DRM master
    # the blank is refused and can leave the panel dark. The RAM installer has
    # its own early blank in config/installer.nix to redraw the complete boot
    # log before a DRM master exists. Dirtyfb uses upstream drm/msm policy.
  };
}
