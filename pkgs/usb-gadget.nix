# SPDX-License-Identifier: MIT
#
# The liuqin USB2 control channel gadget: create the configfs NCM (ECM
# fallback) function and bind the USB2 controller. Shared by the RAM installer
# (config/installer.nix) and the installed system's debug channel
# (modules/liuqin/usb-shell.nix); the two used to carry copies that had already
# drifted apart (log sink, host_addr, strings).
#
# The two consumers differ in exactly two ways, which are arguments here:
#
#   logToConsole   the installer reports on the panel (/dev/console); a system
#                  service reports to its journal.
#   assignAddress  the installer assigns 192.168.7.2/24 itself and raises
#                  /run/liuqin-usb-ready for its udhcpd/telnetd units to wait
#                  on; the installed system leaves usb0 to systemd-networkd and
#                  this script binds the gadget only.
#
# The binary also owns the teardown: `--unbind` detaches the UDC for the
# installed system's ExecStop, so the configfs layout is known in exactly one
# place instead of once here and once in a module-side one-liner.
{ lib, writeShellApplication, coreutils, iproute2, util-linux }:

{ product
, configuration
, logToConsole ? false
, assignAddress ? false
, requestDeviceRole ? true
, superSpeed ? false
}:

let
  assignNetwork = ''
    tries=0
    while [ ! -e /sys/class/net/usb0 ] && [ "$tries" -lt 10 ]; do
      sleep 1
      tries=$((tries + 1))
    done
    [ -e /sys/class/net/usb0 ] || fail "UDC is bound but usb0 did not appear"
    ip link set usb0 up 2>/dev/null || fail "could not bring usb0 up"
    ip address replace 192.168.7.2/24 dev usb0 2>/dev/null \
      || fail "could not assign 192.168.7.2/24 to usb0"
    : >"$ready" || fail "could not create the USB ready marker"
    log "USB $function_name ready at 192.168.7.2/24"
  '';

  bindOnly = ''
    log "USB $function_name bound"
  '';
in
writeShellApplication {
  name = "liuqin-usb-gadget";

  runtimeInputs = [ coreutils iproute2 util-linux ];

  text = ''
    configfs=/sys/kernel/config
    gadget=$configfs/usb_gadget/liuqin
    ready=/run/liuqin-usb-ready

    # `--unbind` is the stop side of the installed system's debug unit
    # (modules/liuqin/usb-shell.nix): detach the UDC and leave the rest of the
    # gadget in place, so a later start rebinds the same function. The RAM
    # installer never stops its gadget - switch_root replaces the whole stage -
    # so nothing calls this there.
    if [ "$#" -gt 0 ] && [ "$1" = --unbind ]; then
      [ "$#" -eq 1 ] || {
        echo "usage: liuqin-usb-gadget [--unbind]" >&2
        exit 2
      }
      if [ -w "$gadget/UDC" ]; then
        printf '\n' >"$gadget/UDC"
      fi
      exit 0
    fi

    log() {
      echo "liuqin-usb: $*"${lib.optionalString logToConsole " >/dev/console 2>/dev/null || true"}
    }

    fail() {
      log "$*"
      rm -f "$ready" 2>/dev/null || true
      exit 1
    }

    mkdir -p "$configfs" /run || fail "could not create configfs or /run"
    if ! mountpoint -q "$configfs"; then
      mount -t configfs configfs "$configfs" 2>/dev/null \
        || fail "could not mount configfs"
    fi
    if [ ! -d "$configfs/usb_gadget" ]; then
      fail "configfs USB gadget support is unavailable"
    fi

    # Idempotent on purpose: the installer runs this once in the initrd and
    # once after switch_root.
    mkdir -p "$gadget" || fail "could not create the USB gadget"
    printf '0x1d6b\n' >"$gadget/idVendor" 2>/dev/null || true
    printf '0x1040\n' >"$gadget/idProduct" 2>/dev/null || true
    printf '0x0100\n' >"$gadget/bcdDevice" 2>/dev/null || true
    printf '%s\n' ${lib.escapeShellArg (if superSpeed then "0x0300" else "0x0200")} >"$gadget/bcdUSB" 2>/dev/null || true

    mkdir -p "$gadget/strings/0x409" || fail "could not create USB string descriptors"
    printf '000000000001\n' >"$gadget/strings/0x409/serialnumber" 2>/dev/null || true
    printf 'Xiaomi Pad 6 Pro mainline\n' >"$gadget/strings/0x409/manufacturer" 2>/dev/null || true
    printf '%s\n' ${lib.escapeShellArg product} >"$gadget/strings/0x409/product" 2>/dev/null || true

    mkdir -p "$gadget/configs/c.1/strings/0x409" \
      || fail "could not create the USB configuration"
    printf '%s\n' ${lib.escapeShellArg configuration} >"$gadget/configs/c.1/strings/0x409/configuration" 2>/dev/null || true
    printf '500\n' >"$gadget/configs/c.1/MaxPower" 2>/dev/null || true

    function_name=
    for candidate in ncm.usb0 ecm.usb0; do
      if [ -d "$gadget/functions/$candidate" ]; then
        function_name=$candidate
        break
      fi
    done
    if [ -z "$function_name" ]; then
      if mkdir "$gadget/functions/ncm.usb0" 2>/dev/null; then
        function_name=ncm.usb0
      elif mkdir "$gadget/functions/ecm.usb0" 2>/dev/null; then
        function_name=ecm.usb0
      else
        fail "could not create an NCM or ECM gadget function"
      fi
    fi
    printf '02:00:00:00:07:02\n' >"$gadget/functions/$function_name/dev_addr" 2>/dev/null || true
    printf '02:00:00:00:07:01\n' >"$gadget/functions/$function_name/host_addr" 2>/dev/null || true
    if [ ! -e "$gadget/configs/c.1/$function_name" ]; then
      ln -s "$gadget/functions/$function_name" "$gadget/configs/c.1/$function_name" 2>/dev/null \
        || fail "could not link the USB function into the configuration"
    fi
    [ -e "$gadget/configs/c.1/$function_name" ] \
      || fail "USB function is not present in the configuration"

    udc_name=
    if [ -r "$gadget/UDC" ]; then
      udc_name=$(cat "$gadget/UDC" 2>/dev/null || true)
      [ "$udc_name" = none ] && udc_name=
    fi
    if [ -z "$udc_name" ]; then
      # No UCSI userspace helper on this device: if the role switch has not
      # selected device mode yet, ask it before looking for a controller.
      # A UCSI-controlled port may already be DFP/host or DP.  The old
      # fallback unconditionally wrote "device" and stole a host role after
      # every notification.  The debug service is an explicit device request,
      # but it must still leave an active host/DP role alone; retrying the unit
      # after the partner is removed lets UCSI select device again.
      active_host=0
      saw_typec=0
      for role_path in /sys/class/usb_role/*/role; do
        [ -r "$role_path" ] || continue
        saw_typec=1
        role=$(cat "$role_path" 2>/dev/null || true)
        case "$role" in
          host|[[]host[]]*|source|[[]source[]]*) active_host=1 ;;
        esac
      done
      if [ "$active_host" -eq 0 ] && ${if requestDeviceRole then "true" else "false"}; then
        for role_path in /sys/class/usb_role/*/role; do
          [ -w "$role_path" ] || continue
          printf 'device\n' >"$role_path" 2>/dev/null || true
        done
      elif [ "$saw_typec" -eq 1 ]; then
        log "UCSI owns the Type-C role; leaving it unchanged"
      fi
      if [ "$active_host" -eq 1 ]; then
        fail "Type-C is in host role; USB debug gadget cannot bind"
      fi
      tries=0
      while [ -z "$udc_name" ] && [ "$tries" -lt 10 ]; do
        for udc_path in /sys/class/udc/*; do
          [ -e "$udc_path" ] || continue
          udc_name=$(basename "$udc_path")
          break
        done
        [ -n "$udc_name" ] && break
        sleep 1
        tries=$((tries + 1))
      done
      if [ -n "$udc_name" ]; then
        if ! printf '%s\n' "$udc_name" >"$gadget/UDC"; then
          fail "failed to bind USB gadget to UDC $udc_name"
        fi
      fi
    fi
    if [ -z "$udc_name" ]; then
      fail "no USB device controller found"
    fi

${if assignAddress then assignNetwork else bindOnly}
  '';
}
