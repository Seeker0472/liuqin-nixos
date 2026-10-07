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
    # driver takes over are not the same: everything the early console drew -
    # the complete boot log, scrollback included - lands in a buffer that is
    # no longer on screen, which is what makes a perfectly healthy boot look
    # like a dead panel.  The blank/unblank below makes fbcon redraw its whole
    # console buffer into the live framebuffer.  Per-draw flushing is the
    # kernel's job (0003-liuqin-display-panel-msm.patch, the msm dirtyfb fix)
    # and needs nothing here.  The RAM installer uses the same command, which
    # is why its log appears on the panel too.
    systemd.services.liuqin-screen-refresh = {
      description = "Redraw the console into the panel framebuffer";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.liuqinScreenRefresh}/bin/liuqin-screen-refresh";
      };
    };
  };
}
