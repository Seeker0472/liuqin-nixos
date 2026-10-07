# SPDX-License-Identifier: MIT
#
# SLPI (sensor DSP) remote-processor lifecycle. The kernel keeps
# qcom_q6v5_pas.slpi_auto_boot=0 (see kernelParams in modules/liuqin/default.nix)
# so the units can provision the SSC registry before the DSP starts; this is
# what starts and stops it.
#
# The unit (modules/liuqin/sensors.nix) uses `start` for ExecStart and `stop`
# for ExecStop. The registry check is run as the FastRPC user that will serve
# it to the DSP; when the command is run manually as a non-root user it checks
# readability with its own privileges instead of failing on runuser.
{ writeShellApplication, coreutils, util-linux }:

writeShellApplication {
  name = "liuqin-slpi";

  runtimeInputs = [ coreutils util-linux ];

  text = ''
    remoteproc_dir=/sys/class/remoteproc
    registry_file=/var/lib/liuqin-sensors/registry/SHA256SUMS
    registry_user=fastrpc
    action=

    usage() {
      echo "usage: liuqin-slpi start|stop [--remoteproc-dir DIR] [--registry-file PATH] [--registry-user USER]" >&2
      exit 2
    }

    while [ "$#" -gt 0 ]; do
      case $1 in
        start|stop) action=$1; shift ;;
        --remoteproc-dir|--registry-file|--registry-user)
          if [ "$#" -lt 2 ]; then
            usage
          fi
          case $1 in
            --remoteproc-dir) remoteproc_dir=$2 ;;
            --registry-file) registry_file=$2 ;;
            --registry-user) registry_user=$2 ;;
          esac
          shift 2
          ;;
        *) usage ;;
      esac
    done
    [ -n "$action" ] || usage

    remote=
    for candidate in "$remoteproc_dir"/remoteproc*; do
      [ -e "$candidate/name" ] || continue
      [ "$(cat "$candidate/name")" = slpi ] || continue
      remote=$candidate
      break
    done
    [ -n "$remote" ] || {
      echo "liuqin-slpi: SLPI remote processor is unavailable" >&2
      exit 1
    }

    case $action in
      start)
        # The registry must be readable by the daemon that serves it to the
        # DSP before the DSP runs.
        if [ "$(id -u)" = 0 ]; then
          runuser -u "$registry_user" -- test -r "$registry_file"
        else
          test -r "$registry_file"
        fi
        state=$(cat "$remote/state")
        [ "$state" != running ] || exit 0
        [ "$state" = offline ] || exit 1
        echo start > "$remote/state"
        ;;
      stop)
        [ "$(cat "$remote/state")" != offline ] || exit 0
        echo stop > "$remote/state"
        ;;
    esac
  '';
}
