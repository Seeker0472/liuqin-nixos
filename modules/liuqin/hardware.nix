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

  # One blank/unblank of the DRM framebuffer makes fbcon redraw its whole
  # buffer, scrollback included, into the memory the panel actually scans.
  # Ported from config/installer.nix, where the panel's log appears for
  # exactly this reason.
  screenRefresh = pkgs.writeShellScriptBin "liuqin-screen-refresh" ''
    set -eu
    for blank in /sys/class/graphics/fb*/blank; do
      [ -e "$blank" ] || continue
      echo 1 > "$blank"
      ${pkgs.coreutils}/bin/sleep 1
      echo 0 > "$blank"
    done
  '';
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
    # The panel is dark until this runs and it is the only log channel, so
    # graphical.target is far too late: measured on the first boot this
    # finished at +98 s while the display driver (and the DRM framebuffer) are
    # up within the first second.  systemd-backlight restores whatever the last
    # session left, so this still has to run after it to win.
    systemd.services.liuqin-backlight-default = {
      description = "Restore the liuqin normal-desktop backlight default";
      wantedBy = [ "basic.target" ];
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

    # --- Panel console repaint --------------------------------------------
    # The bootloader framebuffer and the memory the panel scans after the DRM
    # driver takes over are not the same: everything the early console drew -
    # the complete boot log, scrollback included - lands in a buffer that is
    # no longer on screen, which is what makes a perfectly healthy boot look
    # like a dead panel.  The blank/unblank below makes fbcon redraw its whole
    # console buffer into the live framebuffer.  The installer has carried this
    # service since its own bring-up (config/installer.nix, same script) and
    # that is why its log appears on the panel after a while.  Per-draw
    # flushing is the kernel's job (patch 0012) and needs nothing here.
    systemd.services.liuqin-screen-refresh = {
      description = "Redraw the console into the panel framebuffer";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${screenRefresh}/bin/liuqin-screen-refresh";
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

    # WLAN power save is the largest idle-power knob on the radio chain, and
    # whether it is on is invisible in this closure: mac80211's debugfs is not
    # built and nothing else can read the state, so iw is installed to check
    # it (`iw dev wlp1s0 get power_save`) and to look at link state.
    # NetworkManager would default this on anyway; stating it here keeps the
    # policy with the device instead of with an upstream default.
    networking.networkmanager.wifi.powersave = lib.mkDefault true;
    environment.systemPackages = [ pkgs.iw pkgs.liuqinSensorCheck ];

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
      before = [ "liuqin-wlan-mac.service" "liuqin-bt-preconfigure.service" "sound.target" ];
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
        stage=
        cleanup() {
          [ -z "''${stage:-}" ] || rm -rf "$stage"
          umount "$mnt" 2>/dev/null || true
          rmdir "$mnt" 2>/dev/null || true
        }
        trap cleanup EXIT
        mount -o ro,nodev,nosuid,noexec "$part" "$mnt"

        install -d -m 0700 -o root -g root "$private"

        # The DSP registry mount is writable runtime state. Keep the vendor
        # configuration in the Nix store, but seed the mutable siblings that
        # the firmware removes, creates and updates during regeneration.
        sensor_state=/var/lib/liuqin-sensors
        install -d -m 0750 -o fastrpc -g fastrpc "$sensor_state"
        if [ ! -e "$sensor_state/sns_reg_version" ]; then
          install -m 0640 -o fastrpc -g fastrpc \
            ${sscConfig}/share/qcom/sm8450/Xiaomi/liuqin/sensors/sns_reg_version \
            "$sensor_state/sns_reg_version"
        fi
        for mutable in sensors_list.txt file1 file2; do
          if [ ! -e "$sensor_state/$mutable" ]; then
            install -m 0640 -o fastrpc -g fastrpc /dev/null \
              "$sensor_state/$mutable"
          fi
        done

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
        # sets like the downstream >100-file floor. Stage the complete
        # directory, then exchange it with the active directory in one
        # renameat2 operation so readers never see a half-imported registry.
        stage=$(mktemp -d /var/lib/liuqin-sensors/.registry.XXXXXX)
        chown fastrpc:fastrpc "$stage"
        chmod 0750 "$stage"
        count=0
        for f in "$mnt/sensors/registry/registry/"*; do
          [ -f "$f" ] && [ ! -L "$f" ] || continue
          name=''${f##*/}
          [ -n "$name" ] || exit 1
          case $name in .*|*/*) exit 1 ;; esac
          install -m 0640 -o fastrpc -g fastrpc "$f" "$stage/$name"
          count=$((count + 1))
        done
        [ "$count" -gt 100 ]
        (cd "$stage" && find . -maxdepth 1 -type f ! -name SHA256SUMS \
          -printf '%P\0' | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS)
        chown fastrpc:fastrpc "$stage/SHA256SUMS"
        chmod 0640 "$stage/SHA256SUMS"
        if [ -e /var/lib/liuqin-sensors/registry ] || \
           [ -L /var/lib/liuqin-sensors/registry ]; then
          [ -d /var/lib/liuqin-sensors/registry ] && \
            [ ! -L /var/lib/liuqin-sensors/registry ] || exit 1
          # GNU coreutils' --exchange maps to renameat2(RENAME_EXCHANGE).
          # A filesystem without that primitive fails closed and leaves the
          # old active directory untouched.
          mv --exchange --no-target-directory \
            "$stage" /var/lib/liuqin-sensors/registry
          # The old directory now occupies $stage; cleanup removes it only
          # after the new directory has become active.
        else
          mv "$stage" /var/lib/liuqin-sensors/registry
          stage=
        fi
        if [ ! -e /var/lib/liuqin-sensors/registry/temp.json ]; then
          install -m 0640 -o fastrpc -g fastrpc /dev/null \
            /var/lib/liuqin-sensors/registry/temp.json
        fi
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
      path = with pkgs; [ coreutils gnugrep findutils pkgs.liuqinLibssc ];
      script = ''
        set -eu
        [ -c /dev/fastrpc-sdsp ]
        state_dir=/run/liuqin-sensors
        mkdir -p "$state_dir"
        rm -f "$state_dir"/*-ready "$state_dir"/*-status
        required_failed=0
        for sensor in accelerometer gyroscope light; do
          attempt=1
          ready=0
          while [ "$attempt" -le 4 ]; do
            case $sensor in
              accelerometer) needle='^Accelerometer sensor measurement: X=' ;;
              gyroscope) needle='^Gyroscope sensor measurement: X=' ;;
              light) needle='^Light sensor measurement: ' ;;
            esac
            log="$state_dir/ssccli-$sensor.log"
            if timeout --signal=TERM --kill-after=2s 8s \
              ssccli --sensor="$sensor" --timeout=3 > "$log.tmp" 2>&1 \
              && grep -q "$needle" "$log.tmp"; then
              mv "$log.tmp" "$log"
              grep -c "$needle" "$log" > "$state_dir/$sensor-ready"
              printf 'ready\n' > "$state_dir/$sensor-status"
              ready=1
              break
            fi
            mv "$log.tmp" "$log" 2>/dev/null || :
            attempt=$((attempt + 1))
            [ "$attempt" -le 4 ] || break
            sleep 1
          done
          if [ "$ready" = 0 ]; then
            printf 'failed\n' > "$state_dir/$sensor-status"
            echo "no real $sensor measurement after four bounded attempts" >&2
            [ "$sensor" = accelerometer ] && required_failed=1
          fi
        done
        [ "$required_failed" = 0 ]
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Three sensors are checked sequentially; each sensor has four
        # bounded attempts so a slow SLPI publication cannot hang boot.
        TimeoutStartSec = "150s";
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
