# SPDX-License-Identifier: MIT (expression; payloads are proprietary)
# Package the exact OS2.0.4 sensor assets. Mutable registry contents remain in
# the per-device persist tree and never enter this source repository.
{ lib, runCommand, python3, firmwareAssets }:

runCommand "liuqin-ssc-config" {
  nativeBuildInputs = [ python3 ];
  meta = {
    description = "OS2.0.4 SSC sensor configuration for Xiaomi Pad 6 Pro (liuqin)";
    license = lib.licenses.unfree;
  };
} ''
  set -eu
  asset_root=${firmwareAssets}
  sensor_source="$asset_root/assets/sensors/etc/sensors"
  test -d "$sensor_source/config"
  test -f "$sensor_source/sns_reg_config"

  # Validate the complete sensor asset subtree against its provenance manifest,
  # not only the files copied below. This catches omitted and extra payloads.
  python3 - "$asset_root" <<'PYEOF'
import csv
import hashlib
from pathlib import Path
import sys

root = Path(sys.argv[1])
manifest = root / "MANIFEST.tsv"
with manifest.open(newline="") as stream:
    rows = list(csv.DictReader(stream, delimiter="\t"))
expected = {
    row["output"]: row["sha256"]
    for row in rows
    if row["output"].startswith("assets/sensors/")
}
sensor_root = root / "assets/sensors"
actual = {
    path.relative_to(root).as_posix()
    for path in sensor_root.rglob("*")
    if path.is_file()
}
if not expected or actual != set(expected):
    raise SystemExit(
        f"sensor asset manifest/file-set mismatch: expected={sorted(expected)} actual={sorted(actual)}"
    )
for relative, expected_hash in expected.items():
    digest = hashlib.sha256()
    with (root / relative).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    actual_hash = digest.hexdigest()
    if actual_hash != expected_hash:
        raise SystemExit(f"sensor asset SHA256 mismatch for {relative}: {actual_hash}")
PYEOF

  liuqin="$out/share/qcom/sm8450/Xiaomi/liuqin"
  sensors="$liuqin/sensors"
  mkdir -p "$sensors" "$liuqin/socinfo"
  cp -a "$sensor_source/config" "$sensors/"

  # hexagonrpcd exposes Android's vendor/etc/sensors/sns_reg_config from the
  # physical sensors/sns_reg.conf path. Keep the extracted spelling for
  # provenance and install the same OS2.0.4 bytes under that interface name.
  install -m0644 "$sensor_source/sns_reg_config" "$sensors/sns_reg_config"
  install -m0644 "$sensor_source/sns_reg_config" "$sensors/sns_reg.conf"

  # sensorspd opens this NUL-terminated protocol record through the writable
  # registry directory's parent. Derive it from the single version field in
  # the extracted config rather than carrying an independent payload.
  [ "$(grep -c '^version=' "$sensor_source/sns_reg_config")" = 1 ]
  reg_version=$(sed -n 's/^version=//p' "$sensor_source/sns_reg_config")
  [ "$reg_version" = 12 ] || {
    echo "unsupported OS2 SSC registry version: $reg_version" >&2
    exit 1
  }
  printf 'version=%s\0' "$reg_version" > "$sensors/sns_reg_version"

  ln -s /var/lib/liuqin-sensors/registry "$sensors/registry"
  # The FastRPC /persist/sensors/registry mount is writable runtime state;
  # static vendor files above remain immutable in the Nix store.
  ln -s /var/lib/liuqin-sensors "$liuqin/runtime"

  # The SSC registry contract reads these Qualcomm socinfo attributes through
  # /sys/devices/soc0. These values come from the Liuqin stock boot log
  # (socinfo v0.16, id=531, ver=1.0, hw_plat=8, hw_plat_subtype=0,
  # hw_plat_ver=65536); do not substitute a generic SM8450 value here.
  printf 'MTP\n' > "$liuqin/socinfo/hw_platform"
  printf 'Unknown\n' > "$liuqin/socinfo/platform_subtype"
  printf '0\n' > "$liuqin/socinfo/platform_subtype_id"
  printf '65536\n' > "$liuqin/socinfo/platform_version"
  printf '531\n' > "$liuqin/socinfo/soc_id"
  printf '1.0\n' > "$liuqin/socinfo/revision"

  (cd "$sensors/config" && \
    find . -maxdepth 1 -type f -printf '%P\0' | LC_ALL=C sort -z | \
    xargs -0 sha256sum) > "$sensors/config.SHA256SUMS"
''
