# SPDX-License-Identifier: MIT
#
# Give the QCA6490 Bluetooth controller its provisioned public address before
# BlueZ takes it over. Two controller states are handled: a fresh controller
# that has never been configured (the "Unconfigured index" branch) and one
# already up with the factory placeholder 00:00:00:00:5A:AD. Every MGMT
# request is bounded and the controller's completion reply is required, not
# just btmgmt's exit status (downstream liuqin-bt-public-addr semantics).
#
# The unit (modules/liuqin/hardware.nix) pulls this in via bluetooth.service;
# BlueZ has no declarative option for the public address.
{ writeShellApplication
, bluez
, coreutils
, gawk
, gnugrep
, util-linux
}:

writeShellApplication {
  name = "liuqin-bt-public-addr";

  runtimeInputs = [ bluez coreutils gawk gnugrep util-linux ];

  text = ''
    state=/var/lib/liuqin-private/bluetooth-address
    attempts=30

    while [ "$#" -gt 0 ]; do
      case $1 in
        --state-file)
          if [ "$#" -lt 2 ]; then
            echo "usage: liuqin-bt-public-addr [--state-file PATH]" >&2
            exit 2
          fi
          state=$2
          shift 2
          ;;
        *)
          echo "usage: liuqin-bt-public-addr [--state-file PATH]" >&2
          exit 2
          ;;
      esac
    done

    [ -f "$state" ] && [ ! -L "$state" ]
    [ "$(stat -c '%a:%u:%g' "$state")" = '600:0:0' ]
    addr=$(head -n1 "$state" | tr 'a-f' 'A-F')
    printf '%s\n' "$addr" | grep -Eq '^([0-9A-F]{2}:){5}[0-9A-F]{2}$'
    case $addr in
      00:00:00:00:00:00|FF:FF:FF:FF:FF:FF|00:00:00:00:5A:AD) exit 1 ;;
    esac

    # Bound every individual MGMT request: a request observed waiting on the
    # unit timeout must not be able to park the helper.
    run_mgmt() {
      true | timeout --signal=TERM --kill-after=1s 2s btmgmt "$@"
    }
    # Wait (bounded) for the controller; the rampatch/NVM download over UART
    # finishes on its own schedule.
    for _ in $(seq 1 "$attempts"); do
      config=$(run_mgmt config 2>&1 || true)
      case $config in
        *"Unconfigured index list with 1 item"*)
          idx=$(printf '%s\n' "$config" | awk '/^hci[0-9]+:[[:space:]]+Unconfigured controller/ { line=$1; sub(/^hci/,"",line); sub(/:$/,"",line); print line; exit }')
          [ -n "$idx" ]
          out=$(run_mgmt --index "$idx" public-addr "$addr" 2>&1) || {
            echo "liuqin-bt-preconfigure: btmgmt public-addr failed" >&2
            exit 1
          }
          # Require the controller's completion reply, not btmgmt's exit status
          # alone (downstream asserts "Set Public Address complete").
          printf '%s\n' "$out" | grep -Eq "^hci''${idx}[[:space:]]+Set Public Address complete" || {
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
}
