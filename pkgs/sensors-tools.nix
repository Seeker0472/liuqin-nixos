# SPDX-License-Identifier: MIT
#
# Small, bounded SSC diagnostics.  The sensor silicon is owned by the SLPI
# firmware, so the first useful host-side acceptance test is a real libssc
# measurement rather than an IIO directory count.
#
# Two consumers: the operator and the boot gate in modules/liuqin/hardware.nix,
# which runs `--all --attempts 4 --require accelerometer` so a slow SLPI
# publication cannot hang boot while desktop rotation still requires a real
# accelerometer sample. Sensors that are not required are recorded but cannot
# fail the run.
{ writeShellApplication
, coreutils
, gnugrep
, systemd
, libssc
}:

writeShellApplication {
  name = "liuqin-sensor-check";
  runtimeInputs = [ coreutils gnugrep systemd libssc ];
  text = ''
  set -eu

  usage() {
    status=''${1:-2}
    if [ "$status" -eq 0 ]; then
      cat
    else
      cat >&2
    fi <<'EOF'
usage: liuqin-sensor-check --sensor SENSOR [--state-dir DIRECTORY]
                           [--attempts N] [--require SENSORS]
       liuqin-sensor-check --all [--state-dir DIRECTORY]
                           [--attempts N] [--require SENSORS]

SENSOR is one of accelerometer, gyroscope, or light.  Each selected sensor is
opened sequentially for a bounded sample window through the SLPI/SSC path.
--attempts repeats a failed sample up to N times (default 1).  --require lists
the sensors whose failure fails the check; it defaults to all selected ones.
EOF
    exit "$status"
  }

  state_dir=/run/liuqin-sensors
  selected=
  all=0
  attempts=1
  require=
  while [ "$#" -gt 0 ]; do
    case $1 in
      --sensor)
        [ "$#" -ge 2 ] || usage
        selected=$2
        shift 2
        ;;
      --all)
        all=1
        shift
        ;;
      --state-dir)
        [ "$#" -ge 2 ] || usage
        state_dir=$2
        shift 2
        ;;
      --attempts)
        [ "$#" -ge 2 ] || usage
        case $2 in
          *[!0-9]*|"") usage ;;
        esac
        [ "$2" -ge 1 ] || usage
        attempts=$2
        shift 2
        ;;
      --require)
        [ "$#" -ge 2 ] || usage
        require=$2
        shift 2
        ;;
      --help|-h)
        usage 0
        ;;
      *)
        usage
        ;;
    esac
  done

  if [ "$all" = 1 ]; then
    [ -z "$selected" ] || usage
    sensors='accelerometer gyroscope light'
  else
    [ -n "$selected" ] || usage
    sensors=$selected
  fi
  required=''${require:-$sensors}
  for sensor in $required; do
    case " $sensors " in
      *" $sensor "*) ;;
      *) usage ;;
    esac
  done

  mkdir -p "$state_dir"
  [ -c /dev/fastrpc-sdsp ] || {
    echo 'liuqin-sensor-check: /dev/fastrpc-sdsp is absent' >&2
    exit 1
  }

  # A check may be run manually after the daemon is started, but must never
  # start a second reverse tunnel that races the udev-owned service.
  if ! ${systemd}/bin/systemctl is-active --quiet liuqin-hexagonrpcd-sdsp.service; then
    echo 'liuqin-sensor-check: liuqin-hexagonrpcd-sdsp.service is not active' >&2
    exit 1
  fi

  required_failed=0
  optional_failed=0
  for sensor in $sensors; do
    case $sensor in
      accelerometer) needle='^Accelerometer sensor measurement: X=' ;;
      gyroscope) needle='^Gyroscope sensor measurement: X=' ;;
      light) needle='^Light sensor measurement: ' ;;
      *) echo "liuqin-sensor-check: unsupported sensor: $sensor" >&2; exit 2 ;;
    esac
    log=$state_dir/ssccli-$sensor.log
    tmp=$log.tmp
    # A failed retry must not leave a previous successful ready count beside
    # the new failed status and make the result look healthy to a caller.
    rm -f "$state_dir/$sensor-ready" "$state_dir/$sensor-status" "$tmp"
    ok=0
    status=0
    attempt=1
    while [ "$attempt" -le "$attempts" ]; do
      if timeout --signal=TERM --kill-after=2s 8s \
        ${libssc}/bin/ssccli --sensor="$sensor" --timeout=3 >"$tmp" 2>&1 \
        && ${gnugrep}/bin/grep -q "$needle" "$tmp"; then
        ok=1
        break
      else
        status=$?
        cat "$tmp" > "$log" 2>/dev/null || :
      fi
      attempt=$((attempt + 1))
      if [ "$attempt" -le "$attempts" ]; then
        sleep 1
      fi
    done
    if [ "$ok" = 1 ]; then
      mv "$tmp" "$log"
      ${gnugrep}/bin/grep -c "$needle" "$log" > "$state_dir/$sensor-ready"
      printf 'ready\n' > "$state_dir/$sensor-status"
    else
      rm -f "$tmp"
      printf 'failed\n' > "$state_dir/$sensor-status"
      echo "liuqin-sensor-check: $sensor did not produce a measurement after $attempts attempt(s) (status $status)" >&2
      case " $required " in
        *" $sensor "*) required_failed=1 ;;
        *) optional_failed=1 ;;
      esac
    fi
  done
  if [ "$required_failed" = 0 ] && [ "$optional_failed" = 1 ]; then
    echo 'liuqin-sensor-check: required sensors are ready; some optional checks failed' >&2
  fi
  exit "$required_failed"
  '';
}
