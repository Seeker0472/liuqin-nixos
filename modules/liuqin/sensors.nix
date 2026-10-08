# SPDX-License-Identifier: MIT
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin;

  stateDir = "/var/lib/liuqin-private";

  # The SSC configuration set is Qualcomm/Xiaomi proprietary. Either the
  # operator points sscConfig at their own extraction or registers an archive
  # in the store and pins its hash; without one the SSC stack (and only that
  # stack) is left out - the rest of the per-device provisioning below still
  # runs, because the persist partition is on the device itself.
  hasSscConfig = cfg.sensors.sscConfig != null || cfg.sensors.sscConfigHash != null;

  sscConfig =
    if hasSscConfig then
      pkgs.liuqinSensorsConfig.override {
        inherit (cfg.sensors) sscConfigHash;
        sscConfigArchive = cfg.sensors.sscConfig;
      }
    else
      null;
in
{
  config = lib.mkMerge [
    {
      warnings =
        lib.optional (cfg.enable && cfg.sensors.enable && !hasSscConfig) ''
          hardware.liuqin.sensors.enable is set but no SSC configuration set is
          available, so the Qualcomm sensor stack is left out of this system.
          Extract vendor/etc/sensors/config from your stock ROM dump
          (docs/PORTING-NOTES.md) and either point
          hardware.liuqin.sensors.sscConfig at the archive or register it with
          `nix-store --add-fixed sha256 liuqin-ssc-config.tar.zst` and set
          hardware.liuqin.sensors.sscConfigHash. Set
          hardware.liuqin.sensors.enable = false to silence this.
        '';
    }

    (lib.mkIf cfg.enable {
      # The operator tools on PATH, independent of the SSC configuration set:
      # iw for manual WLAN checks, and liuqin-bt-nv
      # (pkgs/bt-nv/default.nix) - a manual operator tool that rewrites the
      # controller's stock NV/RF table after a Bluetooth power toggle; it is
      # deliberately not wired into any unit.
      environment.systemPackages = [ pkgs.iw pkgs.liuqinBtNv ];

      # --- Provision private per-device state from the persist partition -----
      # Reads persist (sda21) read-only exactly once per boot and installs the
      # WLAN MAC, BT address, speaker calibration and sensor registry into
      # root-only state. Everything below is device-unique; none of it may
      # enter the Nix store or the repo. Missing or malformed per-device data
      # fails the unit closed (pkgs/persist-provision.nix: exact byte counts,
      # a >100-file registry floor, matching the downstream
      # provision-liuqin-from-persist.sh checks).
      systemd.services.liuqin-persist-provision = {
        description = "Provision liuqin per-device data from the persist partition";
        wantedBy = [ "multi-user.target" "sound.target" ];
        # The per-device calr blobs must exist before the firmware union
        # (run-firmware.mount) is mounted, and the union before anything starts
        # a stream on the CS35L41s (the protection firmware's calibration
        # lookup runs inside the first DAPM power-up).  Both stay on
        # sound.target's dependency chain - pinning them to sysinit.target
        # creates an ordering cycle, because sound.target is reached well after
        # it.
        before = [ "liuqin-wlan-mac.service" "liuqin-bt-preconfigure.service" "run-firmware.mount" "sound.target" ];
        after = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # The command owns the payload format and the fail-closed checks
          # (pkgs/persist-provision.nix); the module owns the layout. The SSC
          # seed is optional there: without it the unit warns and provisions
          # the remaining per-device data.
          ExecStart = lib.concatStringsSep " " ([
            "${pkgs.liuqinPersistProvision}/bin/liuqin-persist-provision"
            "--private-dir ${stateDir}"
            "--sensor-dir /var/lib/liuqin-sensors"
            "--firmware-dir /var/lib/firmware"
          ] ++ lib.optional hasSscConfig
            "--ssc-config ${sscConfig}/share/qcom/sm8450/Xiaomi/liuqin");
        };
      };

      users.users.fastrpc = {
        isSystemUser = true;
        group = "fastrpc";
        description = "Qualcomm FastRPC daemon";
      };
      users.groups.fastrpc = { };
      systemd.tmpfiles.rules = [
        "d /var/lib/liuqin-sensors 0750 fastrpc fastrpc -"
        "d /var/lib/liuqin-sensors/registry 0750 fastrpc fastrpc -"
        "d /run/liuqin-sensors 0755 root root -"
        # Extra firmware_loader path (firmware_class.path) for the per-device
        # CS35L41 calibration blobs the provision unit writes.
        "d /var/lib/firmware 0755 root root -"
        "d /var/lib/firmware/cirrus 0755 root root -"
      ];
    })

    (lib.mkIf (cfg.enable && cfg.sensors.enable && hasSscConfig) {
      # The proxy package is in systemPackages for two reasons: nixpkgs' polkit
      # module links /share/polkit-1 from every system package, which installs
      # the net.hadess.SensorProxy.claim-sensor action the rules below reference
      # (polkitd reads it from /run/current-system/sw/share), and monitor-sensor
      # lands on PATH for manual sensor acceptance.  The action file is the
      # package's own; no copy of it lives in this repository.
      environment.systemPackages = [ pkgs.liuqinSensorCheck pkgs.liuqinIioSensorProxy ];

      # iio-sensor-proxy is started with an explicit ExecStart below, so its
      # package is not pulled in through the upstream systemd unit.  Register
      # the package with the system bus as well; this installs the policy which
      # permits the root daemon to own net.hadess.SensorProxy.  Without it the
      # daemon exits cleanly from GLib's name_lost_handler with the misleading
      # "already running" message.
      services.dbus.packages = [ pkgs.liuqinIioSensorProxy ];

      # fastrpc-sdsp: sensor-proxy may see it, and the SSC sample gate starts.
      # This replaces upstream's 80-iio-sensor-proxy.rules (shipped by the proxy
      # package, not installed here) for this device: it adds the patched
      # ssc-accel type and the mount matrix, and points SYSTEMD_WANTS at the gate
      # target instead of the proxy service.
      services.udev.extraRules = ''
        SUBSYSTEM=="misc", KERNEL=="fastrpc-sdsp", GROUP="fastrpc", MODE="0660", \
          ENV{IIO_SENSOR_PROXY_TYPE}+="ssc-accel ssc-light ssc-compass", TAG+="systemd", \
          ENV{SYSTEMD_WANTS}+="liuqin-sensor-stack.target"
        # Portrait panel, landscape-mounted accelerometer (four-pose proven):
        SUBSYSTEM=="misc", KERNEL=="fastrpc-sdsp", ENV{ACCEL_MOUNT_MATRIX}="-1,0,0;0,-1,0;0,0,1"
      '';

      # --- Sensors: SLPI lifecycle, hexagonrpcd, sample gate, sensor proxy --
      systemd.targets.liuqin-sensor-stack = {
        description = "liuqin Qualcomm SSC sensor stack";
        requires = [ "liuqin-hexagonrpcd-sdsp.service" ];
        wants = [ "liuqin-ssc-sample-gate.service" ];
        after = [ "liuqin-hexagonrpcd-sdsp.service" ];
      };

      systemd.services.liuqin-slpi = {
        description = "liuqin sensor processor lifecycle";
        wantedBy = [ "multi-user.target" ];
        requires = [ "liuqin-persist-provision.service" ];
        after = [ "systemd-udevd.service" "systemd-tmpfiles-setup.service" "liuqin-persist-provision.service" ];
        before = [ "liuqin-hexagonrpcd-sdsp.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "20s";
          TimeoutStopSec = "20s";
          ExecStart = "${pkgs.liuqinSlpi}/bin/liuqin-slpi start";
          # Downstream liuqin-slpi stop: power the remoteproc back off.
          ExecStop = "${pkgs.liuqinSlpi}/bin/liuqin-slpi stop";
        };
      };

      systemd.services.liuqin-hexagonrpcd-sdsp = {
        description = "liuqin SLPI FastRPC reverse tunnel";
        requires = [ "liuqin-slpi.service" ];
        after = [ "liuqin-slpi.service" ];
        before = [ "liuqin-ssc-sample-gate.service" ];
        unitConfig.ConditionPathExists = "/dev/fastrpc-sdsp";
        serviceConfig = {
          Type = "simple";
          User = "fastrpc";
          Group = "fastrpc";
          ExecStart = "${pkgs.liuqinHexagonrpc}/bin/hexagonrpcd -f /dev/fastrpc-sdsp -d sdsp -s -R ${sscConfig}/share/qcom/sm8450/Xiaomi/liuqin";
          Restart = "on-failure";
          RestartSec = "2s";
          TimeoutStopSec = "5s";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = false;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = "AF_UNIX AF_LOCAL";
          ReadOnlyPaths = [
            "${sscConfig}/share/qcom/sm8450/Xiaomi/liuqin"
          ];
          ReadWritePaths = [ "/var/lib/liuqin-sensors" ];
          DevicePolicy = "closed";
          DeviceAllow = "/dev/fastrpc-sdsp rw";
        };
        wantedBy = [ "liuqin-sensor-stack.target" ];
        unitConfig.StartLimitIntervalSec = "30s";
        unitConfig.StartLimitBurst = 3;
      };

      systemd.services.liuqin-ssc-sample-gate = {
        description = "liuqin SSC real sensor sample gate";
        requires = [ "liuqin-hexagonrpcd-sdsp.service" ];
        after = [ "liuqin-hexagonrpcd-sdsp.service" ];
        before = [ "iio-sensor-proxy.service" ];
        wantedBy = [ "liuqin-sensor-stack.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # Three sensors are checked sequentially; each sensor has four bounded
          # attempts so a slow SLPI publication cannot hang boot.  Only the
          # accelerometer gates desktop rotation; gyroscope and light are still
          # recorded but cannot fail the unit (pkgs/sensors-tools.nix).
          TimeoutStartSec = "150s";
          ExecStart = "${pkgs.liuqinSensorCheck}/bin/liuqin-sensor-check --all --attempts 4 --require accelerometer";
        };
      };

      # iio-sensor-proxy (patched) only once a real sample exists, and admit
      # the QMI-over-QRTR address family libssc needs.
      systemd.services.iio-sensor-proxy = {
        requires = [ "liuqin-ssc-sample-gate.service" ];
        after = [ "liuqin-ssc-sample-gate.service" ];
        serviceConfig = {
          Type = "dbus";
          BusName = "net.hadess.SensorProxy";
          ExecStart = [ "" "${pkgs.liuqinIioSensorProxy}/libexec/iio-sensor-proxy" ];
          RestrictAddressFamilies = "AF_UNIX AF_LOCAL AF_NETLINK AF_QIPCRTR";
        };
      };

      # gnome-shell only claims the accelerometer when the SensorProxy name
      # appears inside a live greeter session; re-announce after graphical
      # boot and verify a claim landed.
      systemd.services.liuqin-sensor-proxy-refresh = {
        description = "Re-announce iio-sensor-proxy to the greeter's gnome-shell";
        after = [ "graphical.target" ];
        wants = [ "graphical.target" ];
        wantedBy = [ "graphical.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.liuqinSensorProxyRefresh}/bin/liuqin-sensor-proxy-refresh --mode system";
        };
      };

      # Downstream sensors-overlay 49-liuqin-sensorproxy.rules: gnome-shell's
      # first accelerometer claim at login races logind session registration,
      # and upstream's allow_active default denies it for the whole boot.
      # The session refresh helper also needs to restart the proxy from an
      # unprivileged user unit; bound the grant by unit and verb.
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
            if (action.id == "net.hadess.SensorProxy.claim-sensor" && subject.local) {
                return polkit.Result.YES;
            }
        });
        polkit.addRule(function(action, subject) {
            if (action.id == "org.freedesktop.systemd1.manage-units" &&
                action.lookup("unit") == "iio-sensor-proxy.service" &&
                action.lookup("verb") == "restart" &&
                subject.local) {
                return polkit.Result.YES;
            }
        });
      '';

      # The system-level refresh above covers the greeter shell; a desktop
      # session started after it would run the whole login without a claim.
      # Re-announce the proxy name once THIS session's gnome-shell is up and
      # watching (downstream liuqin-sensor-proxy-session-refresh).
      systemd.user.services.liuqin-sensor-proxy-session-refresh = {
        description = "Re-announce iio-sensor-proxy to the session's gnome-shell";
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.liuqinSensorProxyRefresh}/bin/liuqin-sensor-proxy-refresh --mode session";
        };
      };
    })
  ];
}
