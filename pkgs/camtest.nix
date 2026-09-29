# SPDX-License-Identifier: MIT
#
# liuqin-camtest: one command per camera bring-up round on a board whose only
# console is the panel. It prints the media topology and the device's formats,
# captures N frames into a temporary file and - when the frame size is given -
# a checksum per frame, so a corrupt frame or a stalled stream is visible from
# the hashes alone.
#
# Installed only through hardware.liuqin.cameraDebug.enable
# (modules/liuqin/camera-debug.nix), which is off by default: this is bench
# tooling, not a runtime dependency.
#
# Deliberate limits:
#   - the per-frame slicing assumes the device delivers frames back to back; a
#     driver that pads lines (bytesperline > width * bytes-per-pixel) makes the
#     per-frame checksums meaningless, so omit the size for one whole-file hash;
#   - no i2c here on purpose: sensors do not expect i2cdetect's SMBus quick
#     writes. Read chip ids through the sensor driver or with an explicit
#     i2ctransfer (i2c-tools, installed by the same option).
{ writeShellApplication, v4l-utils, coreutils, gnused }:

writeShellApplication {
  name = "liuqin-camtest";
  runtimeInputs = [ v4l-utils coreutils gnused ];
  text = ''
    # liuqin-camtest [video-device] [frames] [bytes-per-frame]
    dev="''${1:-/dev/video0}"
    count="''${2:-10}"
    size="''${3:-}"

    echo "== media topology =="
    media-ctl -p 2>/dev/null || true
    echo
    echo "== formats on $dev =="
    v4l2-ctl -d "$dev" --list-formats-ext 2>/dev/null || true
    echo

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    echo "== capturing $count frames from $dev =="
    v4l2-ctl -d "$dev" --stream-mmap=4 --stream-count="$count" \
      --stream-to="$tmp/frames.raw"

    if [ -n "$size" ]; then
      i=1
      while [ "$i" -le "$count" ]; do
        dd if="$tmp/frames.raw" bs="$size" skip=$((i - 1)) count=1 2>/dev/null \
          | sha256sum | sed "s|^|frame $i |"
        i=$((i + 1))
      done
    else
      ls -l "$tmp/frames.raw"
      sha256sum "$tmp/frames.raw"
    fi
  '';
}
