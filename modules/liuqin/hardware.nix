# SPDX-License-Identifier: MIT
#
# Hardware integration: display/backlight, input firmware in the initrd,
# audio UCM2, WLAN/BT private identity, sensors stack, and the small
# GNOME-facing containment units. All helpers are Nix store paths; state
# directories and systemd units are declared here.
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
    systemd.services.liuqin-backlight-default = {
      description = "Restore the liuqin normal-desktop backlight default";
      wantedBy = [ "graphical.target" ];
      wants = [ "systemd-backlight@backlight:ktz8866-backlight.service" ];
      after = [ "systemd-backlight@backlight:ktz8866-backlight.service" ];
      before = [ "display-manager.service" ];
      path = [ pkgs.coreutils ];
      script = ''
        set -eu
        backlight=/sys/class/backlight/ktz8866-backlight
        case " $(cat /proc/cmdline) " in
          *" androidboot.mode=charger "*) exit 0 ;;
        esac
        [ -d "$backlight" ]
        [ "$(cat "$backlight/max_brightness")" = 2047 ]
        echo 1500 > "$backlight/brightness"
        echo 0 > "$backlight/bl_power"
        [ "$(cat "$backlight/actual_brightness")" = 1500 ]
        [ "$(cat "$backlight/brightness")" = 1500 ]
        [ "$(cat "$backlight/bl_power")" = 0 ]
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # --- Audio: UCM2 for the audioreach card ------------------------------
    # The alsa-ucm-conf package in nixpkgs is extended with the device files
    # via the overlay (see overlay.nix). PipeWire (GNOME default) stays on.

    # --- WLAN private MAC (ath11k QCA6490) --------------------------------
    # The factory MAC lives on the persist partition and is provisioned
    # into root-only state by liuqin-persist-provision.service below; this
    # unit refuses to let NetworkManager see the factory-zero address.
    systemd.services.liuqin-wlan-mac = {
      description = "liuqin private WLAN MAC admission";
      before = [ "NetworkManager.service" "network-pre.target" ];
      path = with pkgs; [ iproute2 coreutils gnugrep gawk ];
      script = ''
        set -eu
        state=${stateDir}/wlan-mac
        [ -f "$state" ] && [ ! -L "$state" ]
        [ "$(stat -c '%a:%u:%g' "$state")" = '600:0:0' ]
        # Single-line framing: anything else is not a provisioned identity.
        [ "$(wc -l < "$state")" = 1 ]
        mac=$(head -n1 "$state" | tr 'A-F' 'a-f')
        printf '%s\n' "$mac" | grep -Eq '^[0-9a-f]{2}(:[0-9a-f]{2}){5}$'
        case $mac in
          00:00:00:00:00:00|ff:ff:ff:ff:ff:ff) exit 1 ;;
        esac
        # Reject multicast identities (odd first octet).
        case ''${mac%%:*} in
          ?1|?3|?5|?7|?9|?b|?d|?f) exit 1 ;;
        esac
        iface=
        for i in $(seq 1 30); do
          for node in /sys/class/net/*; do
            [ -e "$node/device/vendor" ] || continue
            [ "$(cat "$node/device/vendor")" = 0x17cb ] || continue
            [ "$(cat "$node/device/device")" = 0x1103 ] || continue
            iface=''${node##*/}
            break
          done
          [ -n "$iface" ] && break
          sleep 1
        done
        [ -n "$iface" ]
        ip link set dev "$iface" down
        ip link set dev "$iface" address "$mac"
        [ "$(cat "/sys/class/net/$iface/address")" = "$mac" ]
        ip link set dev "$iface" up
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 45;
      };
    };
    systemd.services.NetworkManager = {
      requires = [ "liuqin-wlan-mac.service" ];
      after = [ "liuqin-wlan-mac.service" ];
    };

    # --- Bluetooth public address -----------------------------------------
    systemd.services.liuqin-bt-preconfigure = {
      description = "liuqin QCA6490 public Bluetooth address";
      # When bluetooth.service stops, this helper stops with it.
      partOf = [ "bluetooth.service" ];
      path = with pkgs; [ bluez coreutils gnugrep gawk util-linux ];
      script = ''
        set -eu
        state=${stateDir}/bluetooth-address
        [ -f "$state" ] && [ ! -L "$state" ]
        [ "$(stat -c '%a:%u:%g' "$state")" = '600:0:0' ]
        addr=$(head -n1 "$state" | tr 'a-f' 'A-F')
        printf '%s\n' "$addr" | grep -Eq '^([0-9A-F]{2}:){5}[0-9A-F]{2}$'
        case $addr in
          00:00:00:00:00:00|FF:FF:FF:FF:FF:FF|00:00:00:00:5A:AD) exit 1 ;;
        esac
        # Bound every individual MGMT request: a request observed waiting on
        # the unit timeout must not be able to park the helper (downstream
        # liuqin-bt-public-addr wraps every btmgmt call in timeout 2s).
        run_mgmt() {
          true | timeout --signal=TERM --kill-after=1s 2s btmgmt "$@"
        }
        # Wait (bounded) for the controller; the rampatch/NVM download over
        # UART finishes on its own schedule.
        for i in $(seq 1 30); do
          config=$(run_mgmt config 2>&1 || true)
          case $config in
            *"Unconfigured index list with 1 item"*)
              idx=$(printf '%s\n' "$config" | awk '/^hci[0-9]+:[[:space:]]+Unconfigured controller/ { line=$1; sub(/^hci/,"",line); sub(/:$/,"",line); print line; exit }')
              [ -n "$idx" ]
              out=$(run_mgmt --index "$idx" public-addr "$addr" 2>&1) || {
                echo "liuqin-bt-preconfigure: btmgmt public-addr failed" >&2
                exit 1
              }
              # Require the controller's completion reply, not btmgmt's exit
              # status alone (downstream asserts "Set Public Address complete").
              printf '%s\n' "$out" | grep -Eq "^hci$idx[[:space:]]+Set Public Address complete" || {
                echo "liuqin-bt-preconfigure: controller did not confirm the address" >&2
                exit 1
              }
              exit 0
              ;;
          esac
          info=$(run_mgmt --index 0 info 2>&1 || true)
          case $info in
            *"addr $addr"*) exit 0 ;;
            *"addr 00:00:00:00:5A:AD"*)
              run_mgmt --index 0 power off >/dev/null 2>&1 || true
              out=$(run_mgmt --index 0 public-addr "$addr" 2>&1) || {
                echo "liuqin-bt-preconfigure: btmgmt public-addr failed" >&2
                exit 1
              }
              printf '%s\n' "$out" | grep -Eq "^hci0[[:space:]]+Set Public Address complete" || {
                echo "liuqin-bt-preconfigure: controller did not confirm the address" >&2
                exit 1
              }
              run_mgmt --index 0 power on >/dev/null 2>&1 || true
              exit 0
              ;;
          esac
          sleep 1
        done
        echo "liuqin-bt-preconfigure: controller never reached a usable state" >&2
        exit 1
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 150;
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
    # fails the unit closed (matching the downstream
    # provision-liuqin-from-persist.sh checks: exact byte counts and a
    # >100-file registry floor).
    systemd.services.liuqin-persist-provision = {
      description = "Provision liuqin per-device data from the persist partition";
      wantedBy = [ "multi-user.target" "sound.target" ];
      # CS35L41 calibration must exist before anything opens an audio
      # stream: the driver request_firmware() fires as soon as the sound
      # card is bound. Wanted by (and ordered before) sound.target so the
      # per-channel calr blobs in /var/lib/firmware/cirrus are in place
      # before PipeWire/WirePlumber can touch the card.
      before = [ "liuqin-wlan-mac.service" "liuqin-bt-preconfigure.service" "liuqin-slpi.service" "sound.target" ];
      after = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];
      path = with pkgs; [ coreutils util-linux gnugrep findutils ];
      script = ''
        set -eu
        part=/dev/disk/by-partlabel/persist
        # Downstream provision-liuqin-from-persist.sh semantics: a missing
        # persist partition is a hard failure, not a skip — audio, WLAN and
        # BT identities would silently run uncalibrated/factory otherwise.
        [ -b "$part" ] || {
          echo "liuqin-persist-provision: $part is absent" >&2
          exit 1
        }
        private=${stateDir}
        mnt=$(mktemp -d)
        trap 'umount "$mnt" 2>/dev/null || true; rmdir "$mnt" 2>/dev/null || true' EXIT
        mount -o ro,nodev,nosuid,noexec "$part" "$mnt"

        install -d -m 0700 -o root -g root "$private"

        # Fail closed when the persist payload set is incomplete.
        [ -f "$mnt/wlan/wlan_mac.bin" ]
        [ -f "$mnt/bluetooth/.bt_nv.bin" ]
        [ -f "$mnt/audio/crus_calr.bin" ]
        [ -d "$mnt/sensors/registry/registry" ]

        # WLAN MAC: text "wlan0=AABBCCDDEEFF" -> colon-separated.
        raw=$(cat "$mnt/wlan/wlan_mac.bin")
        hex=$(printf '%s' "$raw" | grep -oP '(?<=wlan0=)[0-9A-Fa-f]{12}')
        printf '%s\n' "$(printf '%s' "$hex" | sed 's/../&:/g; s/:$//' | tr 'A-F' 'a-f')" \
          > "$private/wlan-mac"
        chmod 0600 "$private/wlan-mac"

        # Bluetooth address: 6 raw bytes in order -> colon-separated text.
        bt_hex=$(od -An -tx1 -N6 "$mnt/bluetooth/.bt_nv.bin" | tr -d ' \n')
        [ ''${#bt_hex} -eq 12 ]
        printf '%s\n' "$(printf '%s' "$bt_hex" | sed 's/../&:/g; s/:$//')" \
          > "$private/bluetooth-address"
        chmod 0600 "$private/bluetooth-address"

        # CS35L41 per-channel calibration (4x4 bytes, order TL TR BL BR).
        # The kernel requests cirrus/cs35l41-liuqin-<ch>-calr.bin through
        # the firmware loader. /lib/firmware on the running system is the
        # store-linked kernel-firmware tree (read-only), so the loader is
        # pointed at an extra writable dir via firmware_class.path (see
        # kernelParams in default.nix) and the blobs land in
        # /var/lib/firmware/cirrus/ with the exact 16-byte check.
        calr_size=$(wc -c < "$mnt/audio/crus_calr.bin" | tr -d ' ')
        [ "$calr_size" = 16 ]
        install -d -m 0755 /var/lib/firmware/cirrus
        channels="TL TR BL BR"
        i=0
        for ch in $channels; do
          dd if="$mnt/audio/crus_calr.bin" bs=4 skip=$i count=1 \
            of="/var/lib/firmware/cirrus/cs35l41-liuqin-$ch-calr.bin" status=none
          chmod 0600 "/var/lib/firmware/cirrus/cs35l41-liuqin-$ch-calr.bin"
          i=$((i + 1))
        done

        # SSC sensor registry (fastrpc-readable); refuse implausibly small
        # sets like the downstream >100-file floor.
        install -d -m 0750 -o fastrpc -g fastrpc /var/lib/liuqin-sensors/registry
        count=0
        for f in "$mnt/sensors/registry/registry/"*; do
          [ -f "$f" ] || continue
          install -m 0640 -o fastrpc -g fastrpc \
            "$f" /var/lib/liuqin-sensors/registry/
          count=$((count + 1))
        done
        [ "$count" -gt 100 ]
        (cd /var/lib/liuqin-sensors/registry && sha256sum * > SHA256SUMS)
        chown fastrpc:fastrpc /var/lib/liuqin-sensors/registry/SHA256SUMS
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
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
    services.udev.extraRules = ''
      SUBSYSTEM=="misc", KERNEL=="fastrpc-sdsp", GROUP="fastrpc", MODE="0660", \
        ENV{IIO_SENSOR_PROXY_TYPE}+="ssc-accel", TAG+="systemd", \
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
      after = [ "systemd-udevd.service" "systemd-tmpfiles-setup.service" ];
      before = [ "liuqin-hexagonrpcd-sdsp.service" ];
      path = with pkgs; [ coreutils util-linux ];
      script = ''
        set -eu
        for remote in /sys/class/remoteproc/remoteproc*; do
          [ "$(cat "$remote/name")" = slpi ] || continue
          runuser -u fastrpc -- test -r /var/lib/liuqin-sensors/registry/SHA256SUMS
          state=$(cat "$remote/state")
          [ "$state" != running ] || exit 0
          [ "$state" = offline ] || exit 1
          echo start > "$remote/state"
          exit 0
        done
        echo "SLPI remote processor is unavailable" >&2
        exit 1
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "20s";
        TimeoutStopSec = "20s";
        # Downstream liuqin-slpi stop: power the remoteproc back off.
        ExecStop = pkgs.writeShellScript "liuqin-slpi-stop" ''
          set -eu
          export PATH=${lib.makeBinPath (with pkgs; [ coreutils gnugrep ])}
          for remote in /sys/class/remoteproc/remoteproc*; do
            [ "$(cat "$remote/name")" = slpi ] || continue
            [ "$(cat "$remote/state")" != offline ] || exit 0
            echo stop > "$remote/state"
            exit 0
          done
          echo "SLPI remote processor is unavailable" >&2
          exit 1
        '';
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
          "/var/lib/liuqin-sensors/registry"
        ];
        DevicePolicy = "closed";
        DeviceAllow = "/dev/fastrpc-sdsp rw";
      };
      wantedBy = [ "liuqin-sensor-stack.target" ];
      unitConfig.StartLimitIntervalSec = "30s";
      unitConfig.StartLimitBurst = 3;
    };

    systemd.services.liuqin-ssc-sample-gate = {
      description = "liuqin SSC real accelerometer sample gate";
      requires = [ "liuqin-hexagonrpcd-sdsp.service" ];
      after = [ "liuqin-hexagonrpcd-sdsp.service" ];
      before = [ "iio-sensor-proxy.service" ];
      wantedBy = [ "liuqin-sensor-stack.target" ];
      path = with pkgs; [ coreutils gnugrep pkgs.liuqinLibssc ];
      script = ''
        set -eu
        [ -c /dev/fastrpc-sdsp ]
        state_dir=/run/liuqin-sensors
        mkdir -p "$state_dir"
        attempt=1
        while [ "$attempt" -le 4 ]; do
          if timeout --signal=TERM --kill-after=2s 8s \
            ssccli --sensor=accelerometer --timeout=3 > "$state_dir/ssc.log" 2>&1 \
            && grep -q '^Accelerometer sensor measurement: X=' "$state_dir/ssc.log"; then
            grep -c '^Accelerometer sensor measurement: X=' "$state_dir/ssc.log" \
              > "$state_dir/accelerometer-ready"
            exit 0
          fi
          attempt=$((attempt + 1))
          sleep 1
        done
        echo "no real accelerometer measurement after four bounded attempts" >&2
        exit 1
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "42s";
      };
    };

    # iio-sensor-proxy (patched) only once a real sample exists, and admit
    # the QMI-over-QRTR address family libssc needs.
    systemd.services.iio-sensor-proxy = {
      requires = [ "liuqin-ssc-sample-gate.service" ];
      after = [ "liuqin-ssc-sample-gate.service" ];
      serviceConfig = {
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
      path = with pkgs; [ coreutils gawk procps systemd ];
      script = ''
        set -u
        round=1
        while [ $round -le 5 ]; do
          systemctl restart iio-sensor-proxy.service || :
          sleep 4
          pid=$(pgrep -f iio-sensor-proxy | head -1 || :)
          if [ -n "$pid" ]; then
            a=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null || echo 0)
            sleep 4
            b=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null || echo 0)
            if [ "''${b:-0}" -gt "''${a:-0}" ]; then
              exit 0
            fi
          fi
          round=$((round + 1))
          sleep 10
        done
        exit 1
      '';
      serviceConfig.Type = "oneshot";
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
      path = with pkgs; [ coreutils gawk procps systemd glib ];
      script = ''
        set -u
        owner=
        i=0
        while [ $i -lt 90 ]; do
          owner=$(gdbus call --session -d org.freedesktop.DBus -o /org/freedesktop/DBus \
            -m org.freedesktop.DBus.GetNameOwner org.gnome.Shell 2>/dev/null) && break
          i=$((i + 1))
          sleep 1
        done
        case $owner in
          *':'*) ;;
          *) echo "liuqin-sensor-proxy-session-refresh: gnome-shell never appeared" >&2; exit 1 ;;
        esac
        # The shell name is acquired before mutter's monitor setup completes.
        sleep 3
        round=1
        while [ $round -le 3 ]; do
          systemctl restart iio-sensor-proxy.service || :
          sleep 4
          pid=$(pgrep -f iio-sensor-proxy | head -1 || :)
          if [ -n "$pid" ]; then
            a=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null || echo 0)
            sleep 4
            b=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null || echo 0)
            if [ "''${b:-0}" -gt "''${a:-0}" ]; then
              exit 0
            fi
          fi
          round=$((round + 1))
        done
        echo "liuqin-sensor-proxy-session-refresh: claim never established" >&2
        exit 1
      '';
      serviceConfig.Type = "oneshot";
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
      path = [ pkgs.util-linux pkgs.coreutils ];
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
