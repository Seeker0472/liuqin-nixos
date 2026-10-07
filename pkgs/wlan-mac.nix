# SPDX-License-Identifier: MIT
#
# Admit the provisioned private WLAN MAC to the ath11k QCA6490 (0x17cb:0x1103)
# before NetworkManager can see the factory-zero address. The identity lives in
# root-only state written by liuqin-persist-provision; this command refuses
# anything else and never falls back to the hardware address.
#
# The unit (modules/liuqin/identity.nix) runs it before NetworkManager; there
# is no declarative NetworkManager option for this, because the address is
# per-device state, not a build-time value.
{ writeShellApplication, coreutils, gnugrep, iproute2 }:

writeShellApplication {
  name = "liuqin-wlan-mac";

  runtimeInputs = [ coreutils gnugrep iproute2 ];

  text = ''
    state=/var/lib/liuqin-private/wlan-mac
    vendor=0x17cb
    device=0x1103
    attempts=30

    while [ "$#" -gt 0 ]; do
      case $1 in
        --state-file)
          if [ "$#" -lt 2 ]; then
            echo "usage: liuqin-wlan-mac [--state-file PATH]" >&2
            exit 2
          fi
          state=$2
          shift 2
          ;;
        *)
          echo "usage: liuqin-wlan-mac [--state-file PATH]" >&2
          exit 2
          ;;
      esac
    done

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

    # The driver publishes the device a moment after the firmware completed.
    iface=
    for _ in $(seq 1 "$attempts"); do
      for node in /sys/class/net/*; do
        [ -e "$node/device/vendor" ] || continue
        [ "$(cat "$node/device/vendor")" = "$vendor" ] || continue
        [ "$(cat "$node/device/device")" = "$device" ] || continue
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
}
