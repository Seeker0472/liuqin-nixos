# SPDX-License-Identifier: MIT
#
# Re-announce iio-sensor-proxy while a gnome-shell is watching: the shell only
# considers an accelerometer claim when the SensorProxy name appears after it
# is running.
#
#   system   graphical.target and iio-sensor-proxy are both up, so the greeter
#            can observe one fresh owner.
#   session  wait until this session owns org.gnome.Shell, then restart once.
#
# A missing claim is not an error: mutter deliberately releases or omits its
# claim while laptop posture is active. The restart itself is the contract;
# liuqin-panel-posture owns the tablet-mode fallback.
# Downstream: liuqin-sensor-proxy-refresh / liuqin-sensor-proxy-session-refresh.
{ writeShellApplication
, coreutils
, glib
, systemd
}:

writeShellApplication {
  name = "liuqin-sensor-proxy-refresh";

  runtimeInputs = [ coreutils glib systemd ];

  text = ''
    mode=
    service=iio-sensor-proxy.service

    usage() {
      echo "usage: liuqin-sensor-proxy-refresh --mode system|session [--service UNIT]" >&2
      exit 2
    }

    while [ "$#" -gt 0 ]; do
      case $1 in
        --mode|--service)
          if [ "$#" -lt 2 ]; then
            usage
          fi
          case $1 in
            --mode) mode=$2 ;;
            --service) service=$2 ;;
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
        systemctl restart "$service"
        ;;
      system)
        systemctl restart "$service"
        ;;
    esac
  '';
}
