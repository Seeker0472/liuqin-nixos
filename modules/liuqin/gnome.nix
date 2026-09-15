# SPDX-License-Identifier: MIT
#
# GNOME desktop policy for liuqin: power-key daemon, dconf defaults, logind
# delegation, dmabuf workarounds, and the GSettings schema the session
# helper reads.
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin;
  power-keyd = pkgs.liuqinPowerKeyd;

  # GSettings schema dir for the liuqin power policy, compiled with glib.
  powerSchemas = pkgs.runCommand "liuqin-power-schemas" {
    nativeBuildInputs = [ pkgs.glib ];
  } ''
    mkdir -p $out/share/gsettings-schemas/liuqin-power/glib-2.0/schemas
    cp ${../../data/io.github.liuqin.power.gschema.xml} \
      $out/share/gsettings-schemas/liuqin-power/glib-2.0/schemas/
    glib-compile-schemas $out/share/gsettings-schemas/liuqin-power/glib-2.0/schemas
  '';
in
{
  options.hardware.liuqin.desktop.gnome.enable = lib.mkEnableOption "liuqin GNOME desktop policy";

  config = lib.mkIf (cfg.enable && cfg.desktop.gnome.enable) {
    services.desktopManager.gnome.enable = lib.mkDefault true;
    services.xserver.enable = lib.mkDefault true;
    services.displayManager.gdm.enable = lib.mkDefault true;

    # logind's default power-off on a single press is a desktop-tower
    # assumption; on a tablet the power button is the wake button. All
    # policy is delegated to liuqin-power-keyd below.
    services.logind.settings.Login = {
      HandlePowerKey = "ignore";
      HandlePowerKeyLongPress = "ignore";
    };

    # GTK/WebKit dmabuf corruption on the Adreno 730: force the
    # memory-copy upload path until the kernel coherency story is fixed.
    environment.sessionVariables = {
      GDK_DISABLE = "dmabuf";
      WEBKIT_DISABLE_DMABUF_RENDERER = "1";
    };

    # zenity (dialog) and gnome-session (gnome-session-quit) are looked up on
    # PATH by liuqin-power-menu inside the user session; keep them explicit
    # here since pkgs/power-keyd.nix no longer carries them in a passthru.
    environment.systemPackages = [ pkgs.zenity pkgs.gnome-session powerSchemas ];

    # The power policy schema (read by liuqin-power-key-action through
    # GSETTINGS_SCHEMA_DIR, set by the service environment below).
    environment.pathsToLink = [ "/share/gsettings-schemas/liuqin-power" ];

    systemd.services.liuqin-power-keyd = {
      description = "liuqin Android-style power-key policy";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-udevd.service" "systemd-logind.service" ];
      wants = [ "systemd-logind.service" ];
      path = with pkgs; [
        systemd
        glib # gdbus, gsettings
        util-linux # setpriv, runuser
        coreutils
        getent
      ];
      environment = {
        loginctl = "${pkgs.systemd}/bin/loginctl";
        gdbus = "${pkgs.glib}/bin/gdbus";
        gsettings = "${pkgs.glib}/bin/gsettings";
        systemctl = "${pkgs.systemd}/bin/systemctl";
        systemd_run = "${pkgs.systemd}/bin/systemd-run";
        power_menu = "${power-keyd}/libexec/liuqin-power-menu";
        setpriv = "${pkgs.util-linux}/bin/setpriv";
        getent = "${pkgs.getent}/bin/getent";
        test_bin = "${pkgs.coreutils}/bin/test";
        GSETTINGS_SCHEMA_DIR = "${powerSchemas}/share/gsettings-schemas/liuqin-power/glib-2.0/schemas";
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${power-keyd}/libexec/liuqin-power-keyd";
        Restart = "always";
        RestartSec = 1;
        TimeoutStopSec = 7;        UMask = "0077";
        RuntimeDirectory = "liuqin-power-keyd";
        RuntimeDirectoryMode = "0755";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        # Downstream 20-liuqin-session-runtime.conf: the daemon drives the
        # session's dconf/GSettings over /run/user, so persistent homes stay
        # read-only rather than inaccessible.
        ProtectHome = "no";
        ReadOnlyPaths = [ "/home" "/root" ];
        ReadWritePaths = [ "/run/user" ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = "AF_UNIX";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        CapabilityBoundingSet = "CAP_SETUID CAP_SETGID";
      };
      # Bounded restart: same convention as liuqin-hexagonrpcd-* so a
      # persistently crashing daemon does not spin forever.
      unitConfig.StartLimitIntervalSec = "30s";
      unitConfig.StartLimitBurst = 3;
    };

    # dconf defaults: scaling, on-screen keyboard, idle blanking, and the
    # delegation of the power button to liuqin-power-keyd (both the user
    # profile and the gdm greeter profile).
    programs.dconf.enable = true;
    environment.etc."dconf/db/local.d/00-liuqin".text = ''
      [org/gnome/desktop/interface]
      scaling-factor=uint32 2

      [org/gnome/desktop/a11y/applications]
      screen-keyboard-enabled=true

      [org/gnome/desktop/session]
      idle-delay=uint32 300

      [org/gnome/settings-daemon/plugins/power]
      power-button-action='nothing'
      sleep-inactive-ac-type='nothing'
      sleep-inactive-battery-type='nothing'

      [org/gnome/desktop/screensaver]
      lock-enabled=true
    '';
    environment.etc."dconf/db/gdm.d/00-liuqin-power".text = ''
      [org/gnome/settings-daemon/plugins/power]
      power-button-action='nothing'
    '';
  };
}
