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
    cp ${../../pkgs/power-keyd/io.github.liuqin.power.gschema.xml} \
      $out/share/gsettings-schemas/liuqin-power/glib-2.0/schemas/
    glib-compile-schemas $out/share/gsettings-schemas/liuqin-power/glib-2.0/schemas
  '';

  # Seeded mutter display configuration: the built-in panel's fixed rotation
  # for the laptop posture (the option description carries the semantics).
  monitorsXml = pkgs.writeText "liuqin-monitors.xml" ''
    <monitors version="2">
      <configuration>
        <logicalmonitor>
          <x>0</x>
          <y>0</y>
          <scale>2</scale>
          <primary>yes</primary>
          <transform>
            <rotation>${cfg.desktop.gnome.panelOrientation}</rotation>
          </transform>
          <monitor>
            <connector>DSI-1</connector>
            <vendor>unknown</vendor>
            <product>unknown</product>
            <serial>unknown</serial>
          </monitor>
        </logicalmonitor>
      </configuration>
    </monitors>
  '';

  sessionHome =
    config.users.users.${cfg.desktop.gnome.sessionUser}.home
    or "/home/${cfg.desktop.gnome.sessionUser}";
in
{
  options.hardware.liuqin.desktop.gnome = {
    enable = lib.mkEnableOption "liuqin GNOME desktop policy";

    sessionUser = lib.mkOption {
      type = lib.types.str;
      default = "liuqin";
      description = ''
        Session user whose home receives the seeded ``monitors.xml``.
      '';
    };

    panelOrientation = lib.mkOption {
      type = lib.types.enum [ "normal" "left" "right" "upside-down" ];
      default = "right";
      description = ''
        Fixed rotation for the built-in panel, seeded into
        ``~/.config/monitors.xml`` as the mutter display configuration.  The
        panel is natively portrait (1800x2880), while the keyboard folio
        stands the tablet in landscape, so the laptop posture - keyboard
        deployed in front, which the tablet-mode hall reports as
        SW_TABLET_MODE=0 - needs an explicit transform to stand upright;
        "right" is the landscape pose measured on the unit.

        Tablet mode keeps GNOME in charge: while the keyboard is folded onto
        the back (SW_TABLET_MODE=1, "no keyboard attached" in the switch's
        own semantics) mutter manages the orientation from the
        accelerometer and this transform does not apply, so rotation follows
        gravity there.

        The file is seeded once and never overwritten - a later change made
        by the user, or written by GNOME's own display settings, wins over
        the next activation.
      '';
    };
  };

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

    # FIXME(lid-suspend-loop, 2026-10-07): HandleLidSwitch is not set here, so
    # logind's default (suspend) applies.  The loop this described is logind's
    # own lid recheck, not a client request: while the lid is closed,
    # `button_recheck()` re-runs the lid action on every event-loop turn, gated
    # only by `HoldoffTimeoutUSec` (30 s, re-armed on every sleep start and
    # counting monotonic time, which stops during suspend) - hence a new
    # suspend ~28 s after each resume as long as the still-unidentified wake
    # source keeps waking the unit.  `Suspending...` is logind's own message
    # (the D-Bus `Suspend()` path does not log it), so there is no requester to
    # find, and USB cannot be the waker (the host sees the device disconnect;
    # dwc3/USB wakeup is disabled).  Decide the cover policy here once the
    # waker is measured - see docs/TODO/LID-SUSPEND-LOOP.md.

    # GTK/WebKit dmabuf corruption on the Adreno 730: force the
    # memory-copy upload path until the kernel coherency story is fixed.
    environment.sessionVariables = {
    # GDK_DISABLE=dmabuf deliberately NOT set: measured 2026-10-03, the
    # dmabuf path works and the variable only makes GTK4's camera sink fail
    # to transform frames (black viewfinder).  The actual camera-path issue
    # is the pipewire/portal format handshake, tracked in
    # docs/PORTING-NOTES.md (Camera).
      WEBKIT_DISABLE_DMABUF_RENDERER = "1";
    };

    # zenity (dialog) and gnome-session (gnome-session-quit) are looked up on
    # PATH by liuqin-power-menu inside the user session; keep them explicit
    # here since pkgs/power-keyd/default.nix no longer carries them in a passthru.
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
        TimeoutStopSec = 7;
        UMask = "0077";
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
    #
    # These go through programs.dconf.profiles: nixpkgs' dconf module turns
    # /etc/dconf into a symlink to the generated dconf-system-config store
    # path, so environment.etc."dconf/db/..." entries both fail to build
    # (mkdir inside the read-only symlink target) and would never be found -
    # there is no db/local.d in the generated tree.  Keyfiles are used instead
    # of `settings` so the values keep their explicit GVariant types
    # (scaling-factor must stay uint32).
    programs.dconf.enable = true;
    programs.dconf.profiles.user.databases = [
      {
        keyfiles = [
          (pkgs.writeTextDir "00-liuqin" ''
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
          '')
        ];
      }
    ];
    programs.dconf.profiles.gdm.databases = [
      {
        keyfiles = [
          (pkgs.writeTextDir "00-liuqin-power" ''
            [org/gnome/settings-daemon/plugins/power]
            power-button-action='nothing'
          '')
        ];
      }
    ];

    # Mutter neither restores the configured transform when tablet mode ends
    # (the panel keeps whatever the accelerometer last produced) nor re-claims
    # the accelerometer after a laptop-posture interlude; the loop repairs
    # both from the driver's derived folio switch.  See pkgs/panel-posture.nix.
    systemd.user.services.liuqin-panel-posture = {
      description = "Keep the panel transform right across folio postures";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.liuqinPanelPosture}/bin/liuqin-panel-posture";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    # Seed ~/.config/monitors.xml for the session user.  `d` with mode `-`
    # leaves the existing ~/.config ownership and mode alone; `C` copies the
    # file only when it is absent, so a configuration the user changed later
    # (or one mutter rewrote itself) is never clobbered by an activation.
    systemd.tmpfiles.rules = [
      "d ${sessionHome}/.config - ${cfg.desktop.gnome.sessionUser} users -"
      "C ${sessionHome}/.config/monitors.xml 0644 ${cfg.desktop.gnome.sessionUser} users - ${monitorsXml}"
    ];
  };
}
