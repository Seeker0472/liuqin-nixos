# SPDX-License-Identifier: MIT
#
# Small, bounded SSC diagnostics.  The sensor silicon is owned by the SLPI
# firmware, so the first useful host-side acceptance test is a real libssc
# measurement rather than an IIO directory count.
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
       liuqin-sensor-check --all [--state-dir DIRECTORY]

SENSOR is one of accelerometer, gyroscope, or light.  Each selected sensor is
opened sequentially for a bounded sample window through the SLPI/SSC path.
EOF
    exit "$status"
  }

  state_dir=/run/liuqin-sensors
  selected=
  all=0
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

  failed=0
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
    rm -f "$state_dir/$sensor-ready" "$state_dir/$sensor-status"
    rm -f "$tmp"
    if timeout --signal=TERM --kill-after=2s 8s \
      ${libssc}/bin/ssccli --sensor="$sensor" --timeout=3 >"$tmp" 2>&1 \
      && ${gnugrep}/bin/grep -q "$needle" "$tmp"; then
      mv "$tmp" "$log"
      ${gnugrep}/bin/grep -c "$needle" "$log" > "$state_dir/$sensor-ready"
      printf 'ready\n' > "$state_dir/$sensor-status"
    else
      status=$?
      cat "$tmp" > "$log" 2>/dev/null || :
      rm -f "$tmp"
      printf 'failed=%s\n' "$status" > "$state_dir/$sensor-status"
      echo "liuqin-sensor-check: $sensor did not produce a measurement" >&2
      failed=1
    fi
  done
  exit "$failed"
  '';
}
