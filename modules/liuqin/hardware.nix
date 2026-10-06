# SPDX-License-Identifier: MIT
#
# Hardware integration: display/backlight, input firmware in the initrd,
# audio UCM2, WLAN/BT private identity, sensors stack, and the small
# GNOME-facing containment units.
#
# Only the declarative half lives here: state directories, unit ordering,
# sandboxing and polkit. Every command a unit runs is a package from the
# overlay (pkgs/*.nix, exposed as pkgs.liuqin*), and the device-unique paths
# travel as arguments so each command stays runnable by hand, including
# against fixture trees with no tablet involved.
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin;

  stateDir = "/var/lib/liuqin-private";

  sscConfig = pkgs.liuqinSensorsConfig.override {
    inherit (cfg.sensors) sscConfigHash;
  };
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.sensors.enable -> cfg.sensors.sscConfigHash != null;
        message = ''
          hardware.liuqin.sensors.sscConfigHash is unset. Extract
          vendor/etc/sensors/config from your stock ROM dump
          (docs/PORTING-NOTES.md), add the archive with
          `nix-store --add-fixed sha256 liuqin-ssc-config.tar.zst`, and set
          the option to its sha256 (SRI form).
        '';
      }
    ];
    # TODO(touch-drift): with an external display connected the touchscreen is
    # mapped to the wrong output by Mutter and the finger coordinates drift.
    # Measured root cause: the touchscreen is an I2C device with neither USB
    # ids (0000:0000) nor a reported resolution, and the built-in DSI panel
    # reports no vendor/product either, so Mutter's "same vendor/product, same
    # size, built-in panel" heuristics have nothing to match on and it falls
    # back to the wrong logical monitor.  The driver itself is clean: it
    # reports ABS_MT_POSITION in the panel's native portrait frame
    # (0..1799 x 0..2879), verified by reading evdev directly.
    # Two fixes were tried and *reverted* - do not repeat them blindly:
    #   1. gsettings .../touchscreens/0000:0000/ output ['unknown','unknown',
    #      'unknown'] (or the 4-element form with 'DSI-1'): matches no monitor
    #      spec, the touchscreen ends up bound to nothing and goes dead.
    #   2. input_abs_set_res() for the finger device (to let libinput derive a
    #      size): the touch went dead at the evdev level, 0 events; cause
    #      unknown, the change was removed again.
    # See docs/PORTING-NOTES.md ("Touch and input") for the current status and
    # the remaining options (synthetic EDID for the DSI connector, or a
    # Mutter-side mapping).
    # --- Firmware the patched drivers request from userspace --------------
    # nvt_ts probes on the SPI bus very early and request_firmware() must
    # succeed there; the panel/keyboard/GPU/DSP payloads below come from the
    # operator's stock ROM dump (requireFile placeholders until pinned).
    hardware.firmware = [ pkgs.liuqinFirmware ];
    hardware.enableRedistributableFirmware = lib.mkDefault true;

    # The touchscreen (nvt_ts) request_firmware() fires during probe, before
    # switch_root, so the firmware tree must be in the initrd too.
    # The initrd's /lib is a read-only symlink to the kernel module store, so
    # placing a second tree below /lib/firmware makes systemd's initrd image
    # builder fail. Use the same writable firmware_class.path that carries
    # the device-specific calibration files after switch-root.
    boot.initrd.systemd.contents."/var/lib/firmware".source =
      "${pkgs.liuqinFirmware}/lib/firmware";

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
    # kernel's job (patch 0012) and needs nothing here.  The RAM installer
    # uses the same command, which is why its log appears on the panel too.
    systemd.services.liuqin-screen-refresh = {
      description = "Redraw the console into the panel framebuffer";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.liuqinScreenRefresh}/bin/liuqin-screen-refresh";
      };
    };

    # --- Audio: UCM2 for the audioreach card ------------------------------
    # alsa-lib resolves its UCM2 tree through $out/share/alsa/ucm2, a symlink to
    # the alsa-ucm-conf store path, and honours ALSA_CONFIG_UCM2 as an
    # override.  The device files therefore live in liuqinAlsaUcm - a leaf copy
    # of the upstream tree plus the two liuqin files (pkgs/alsa-ucm.nix) -
    # rather than in a patched alsa-ucm-conf, which would change alsa-lib and
    # rebuild every audio consumer in the closure.  The user units get the
    # variable explicitly because a lingering systemd --user session does not
    # necessarily inherit the pam_env session environment.
    environment.variables.ALSA_CONFIG_UCM2 = "${pkgs.liuqinAlsaUcm}/share/alsa/ucm2";
    systemd.user.services.pipewire.environment.ALSA_CONFIG_UCM2 =
      "${pkgs.liuqinAlsaUcm}/share/alsa/ucm2";
    systemd.user.services.wireplumber.environment.ALSA_CONFIG_UCM2 =
      "${pkgs.liuqinAlsaUcm}/share/alsa/ucm2";

    # --- WLAN private MAC (ath11k QCA6490) --------------------------------
    # The factory MAC lives on the persist partition and is provisioned
    # into root-only state by liuqin-persist-provision.service below; this
    # unit refuses to let NetworkManager see the factory-zero address.
    systemd.services.liuqin-wlan-mac = {
      description = "liuqin private WLAN MAC admission";
      before = [ "NetworkManager.service" "network-pre.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 45;
        ExecStart = "${pkgs.liuqinWlanMac}/bin/liuqin-wlan-mac --state-file ${stateDir}/wlan-mac";
      };
    };
    systemd.services.NetworkManager = {
      requires = [ "liuqin-wlan-mac.service" ];
      after = [ "liuqin-wlan-mac.service" ];
    };

    # WLAN power save is the largest idle-power knob on the radio chain, and
    # whether it is on is invisible in this closure: mac80211's debugfs is not
    # built and nothing else can read the state, so iw is installed to check
    # it (`iw dev wlp1s0 get power_save`) and to look at link state.
    # NetworkManager would default this on anyway; stating it here keeps the
    # policy with the device instead of with an upstream default.
    networking.networkmanager.wifi.powersave = lib.mkDefault true;
    # The proxy package is in systemPackages for two reasons: nixpkgs' polkit
    # module links /share/polkit-1 from every system package, which installs
    # the net.hadess.SensorProxy.claim-sensor action the rules below reference
    # (polkitd reads it from /run/current-system/sw/share), and monitor-sensor
    # lands on PATH for manual sensor acceptance.  The action file is the
    # package's own; no copy of it lives in this repository.
    #
    # liuqin-bt-nv (pkgs/bt-nv.nix) is a manual operator tool on PATH:
    # rewriting the controller's stock NV/RF table after a Bluetooth power
    # toggle.  It is deliberately not wired into any unit.
    environment.systemPackages = [ pkgs.iw pkgs.liuqinBtNv pkgs.liuqinSensorCheck pkgs.liuqinIioSensorProxy ];

    # iio-sensor-proxy is started with an explicit ExecStart below, so its
    # package is not pulled in through the upstream systemd unit.  Register
    # the package with the system bus as well; this installs the policy which
    # permits the root daemon to own net.hadess.SensorProxy.  Without it the
    # daemon exits cleanly from GLib's name_lost_handler with the misleading
    # "already running" message.
    services.dbus.packages = [ pkgs.liuqinIioSensorProxy ];

    # --- Bluetooth public address -----------------------------------------
    systemd.services.liuqin-bt-preconfigure = {
      description = "liuqin QCA6490 public Bluetooth address";
      # When bluetooth.service stops, this helper stops with it.
      partOf = [ "bluetooth.service" ];
      # The controller is unconfigured on every boot (its address is volatile)
      # and this unit's "Set Public Address" is what drives the kernel's
      # unconfigured -> configured transition; that transition re-runs the
      # whole QCA setup (hci_qca sets HCI_QUIRK_NON_PERSISTENT_SETUP whenever
      # it owns the chip's power lines, as the wcn6855-pmu pwrseq path does),
      # re-downloading rampatch/NVM through firmware_class.path.  That path is
      # only usable once liuqin-firmware-path has mounted the union: the
      # stage-2 root's /var/lib/firmware carries calibration only and there is
      # no /lib/firmware, so a setup that runs first finds no qca file at all,
      # this unit fails and bluetooth.service (which Requires= it) never
      # starts.  Measured on the unit: the union finished at 12.795 s and the
      # re-download began at 12.820 s, a margin nothing guarantees.
      wants = [ "liuqin-firmware-path.service" ];
      after = [ "liuqin-firmware-path.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 150;
        ExecStart = "${pkgs.liuqinBtPublicAddr}/bin/liuqin-bt-public-addr --state-file ${stateDir}/bluetooth-address";
      };
    };
    systemd.services.bluetooth = {
      requires = [ "liuqin-bt-preconfigure.service" ];
      after = [ "liuqin-bt-preconfigure.service" ];
    };

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
      # The per-device calr blobs must exist before liuqin-firmware-path
      # builds the firmware union, and the union before anything starts a
      # stream on the CS35L41s (the protection firmware's calibration lookup
      # runs inside the first DAPM power-up).  Both stay on sound.target's
      # dependency chain - pinning them to sysinit.target creates an ordering
      # cycle, because sound.target is reached well after it.
      before = [ "liuqin-wlan-mac.service" "liuqin-bt-preconfigure.service" "liuqin-firmware-path.service" "sound.target" ];
      after = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # The command owns the payload format and the fail-closed checks
        # (pkgs/persist-provision.nix); the module owns the layout.
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.liuqinPersistProvision}/bin/liuqin-persist-provision"
          "--private-dir ${stateDir}"
          "--sensor-dir /var/lib/liuqin-sensors"
          "--firmware-dir /var/lib/firmware"
          "--ssc-config ${sscConfig}/share/qcom/sm8450/Xiaomi/liuqin"
        ];
      };
    };

    # The firmware loader reads exactly one directory (firmware_class.path;
    # fw_path_para is a single char[256] with no ':') and /lib/firmware does
    # not exist on NixOS, so point it at an overlay of the three trees the
    # board needs: the vendor CS35L41 payloads (they must shadow
    # linux-firmware's same-named files in the system tree), the system
    # firmware tree and the per-device calibration records under
    # /var/lib/firmware.  See pkgs/firmware-path.nix; the unit only warns
    # when the persist data is absent, so a device without calibration still
    # boots.
    systemd.services.liuqin-firmware-path = {
      description = "Firmware union (overlay of vendor, system and calibration trees)";
      wantedBy = [ "sound.target" ];
      before = [ "sound.target" ];
      after = [ "liuqin-persist-provision.service" "local-fs.target" ];
      # A re-provision (e.g. after repairing the persist partition) must be
      # followed by a fresh mount: the overlay reads its lower layers only
      # once, so the union restarts together with the provisioner instead of
      # keeping the previous calibration view.
      partOf = [ "liuqin-persist-provision.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.liuqinFirmwarePath}/bin/liuqin-firmware-path";
        ExecStop = "-${pkgs.util-linux}/bin/umount /run/firmware";
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

    # --- Gunyah node containment ------------------------------------------
    # ABL's DTBO injects /hypervisor (compatible "qcom,gunyah-vm") into the
    # live tree; systemd-detect-virt keys off it and sends GSD down VM code
    # paths. The kernel never binds a driver to the node, so a bind mount of
    # an empty directory over the devicetree export restores an honest
    # "none" for userspace readers.
    systemd.services.liuqin-hide-gunyah-node = {
      description = "Hide the ABL-injected Gunyah /hypervisor node from userspace";
      wantedBy = [ "sysinit.target" ];
      unitConfig = {
        DefaultDependencies = false;
        Conflicts = "shutdown.target";
        Before = [ "sysinit.target" "shutdown.target" ];
        ConditionPathExists = "/sys/firmware/devicetree/base/hypervisor";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /run/liuqin-empty";
        ExecStart = "${pkgs.util-linux}/bin/mount --bind /run/liuqin-empty /sys/firmware/devicetree/base/hypervisor";
        ExecStop = "${pkgs.util-linux}/bin/umount /sys/firmware/devicetree/base/hypervisor";
      };
    };
  };
}
