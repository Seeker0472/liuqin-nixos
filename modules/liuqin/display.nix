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
    # The bootloader framebuffer and the memory the panel scans after the DRM
    # driver takes over are not the same, so everything the early console drew
    # used to land in a buffer that is no longer on screen - which is what
    # made a healthy boot look like a dead panel.  The fix for that is the
    # kernel's per-draw flushing (0003-liuqin-display-panel-msm.patch, the msm
    # dirtyfb fix); the blank/unblank workaround that used to live here
    # (`liuqin-screen-refresh`) is gone: measured 2026-10-07, its late blank
    # is refused once a DRM master exists (GDM at ~10 s), so the display is
    # left blanked with nothing to undo it - it was turning a working panel
    # into a dark screen.  The RAM installer still runs the same command (its
    # own unit in config/installer.nix), where the blank lands before any
    # master exists and only costs a one-second blink.
  };
}
