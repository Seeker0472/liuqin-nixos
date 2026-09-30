# SPDX-License-Identifier: MIT
#
# Re-announce iio-sensor-proxy while a gnome-shell is watching: the shell only
# claims the accelerometer when the SensorProxy name appears *after* it is
# running, so a proxy that started before the shell is never claimed.
#
#   system   the greeter's shell, from graphical.target. There is no session
#            bus to wait on from the system context, so this retries with
#            backoff for as long as a slow greeter can plausibly take.
#   session  this session's shell: wait until org.gnome.Shell owns its name on
#            the session bus, then restart the proxy.
#
# Both modes verify that a claim actually landed - a claiming client is what
# makes the proxy's CPU time advance - instead of trusting the restart.
# Downstream: liuqin-sensor-proxy-refresh / liuqin-sensor-proxy-session-refresh.
{ writeShellApplication
, coreutils
, gawk
, glib
, procps
, systemd
}:

writeShellApplication {
  name = "liuqin-sensor-proxy-refresh";

  runtimeInputs = [ coreutils gawk glib procps systemd ];

  text = ''
    mode=
    service=iio-sensor-proxy.service
    process=iio-sensor-proxy

    usage() {
      echo "usage: liuqin-sensor-proxy-refresh --mode system|session [--service UNIT] [--process PATTERN]" >&2
      exit 2
    }

    while [ "$#" -gt 0 ]; do
      case $1 in
        --mode|--service|--process)
          if [ "$#" -lt 2 ]; then
            usage
          fi
          case $1 in
            --mode) mode=$2 ;;
            --service) service=$2 ;;
            --process) process=$2 ;;
          esac
          shift 2
          ;;
        *) usage ;;
      esac
    done
    case $mode in
      system|session) ;;
      *) usage ;;
    esac

    # Restart the proxy and wait for a claim: sample the proxy's CPU time
    # before and after the window in which the shell can claim.
    restart_and_verify() {
      rounds=$1
      pause=$2
      round=1
      while [ "$round" -le "$rounds" ]; do
        systemctl restart "$service" || :
        sleep 4
        pid=$(pgrep -f "$process" | head -1 || :)
        if [ -n "$pid" ]; then
          a=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null || echo 0)
          sleep 4
          b=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null || echo 0)
          if [ "''${b:-0}" -gt "''${a:-0}" ]; then
            return 0
          fi
        fi
        round=$((round + 1))
        [ "$pause" -eq 0 ] || sleep "$pause"
      done
      return 1
    }

    case $mode in
      session)
        owner=
        i=0
        while [ "$i" -lt 90 ]; do
          owner=$(gdbus call --session -d org.freedesktop.DBus -o /org/freedesktop/DBus \
            -m org.freedesktop.DBus.GetNameOwner org.gnome.Shell 2>/dev/null) && break
          i=$((i + 1))
          sleep 1
        done
        case $owner in
          *':'*) ;;
          *)
            echo "liuqin-sensor-proxy-refresh: gnome-shell never appeared" >&2
            exit 1
            ;;
        esac
        # The shell name is acquired before mutter's monitor setup completes.
        sleep 3
        restart_and_verify 3 0 || {
          echo "liuqin-sensor-proxy-refresh: claim never established" >&2
          exit 1
        }
        ;;
      system)
        restart_and_verify 5 10 || exit 1
        ;;
    esac
  '';
}
