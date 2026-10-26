# SPDX-License-Identifier: MIT (expression; payloads are proprietary)
{ lib, runCommand, python3, firmwareAssets }:

runCommand "liuqin-fpc-firmware" {
  nativeBuildInputs = [ python3 ];
  meta.license = lib.licenses.unfree;
} ''
  set -eu
  asset_root=${firmwareAssets}
  src="$asset_root/assets/fingerprint"
  test -f "$src/SHA256.json"
  for required in fpcliu.mdt fpcliu.b00 fpcliu.b01 fpcliu.b02 fpcliu.b03 \
                  fpcliu.b04 fpcliu.b05 fpcliu.b06 fpcliu.b07 fpcliu.b08; do
    test -f "$src/$required" || {
      echo "FPC firmware missing: $required" >&2
      exit 1
    }
  done

  python3 - "$asset_root" <<'PY'
import csv
import hashlib
import json
from pathlib import Path
import sys

asset_root = Path(sys.argv[1])
with (asset_root / "MANIFEST.tsv").open(newline="") as stream:
    rows = list(csv.DictReader(stream, delimiter="\t"))
expected_outputs = {
    row["output"]: row["sha256"]
    for row in rows
    if row["output"].startswith("assets/fingerprint/")
}
fingerprint_root = asset_root / "assets/fingerprint"
actual_outputs = {
    path.relative_to(asset_root).as_posix()
    for path in fingerprint_root.rglob("*")
    if path.is_file()
}
if not expected_outputs or actual_outputs != set(expected_outputs):
    raise SystemExit(
        f"FPC asset manifest/file-set mismatch: expected={sorted(expected_outputs)} actual={sorted(actual_outputs)}"
    )
for relative, expected_hash in expected_outputs.items():
    digest = hashlib.sha256()
    with (asset_root / relative).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    actual_hash = digest.hexdigest()
    if actual_hash != expected_hash:
        raise SystemExit(f"FPC asset SHA256 mismatch for {relative}: {actual_hash}")

root = fingerprint_root
manifest = json.loads((root / "SHA256.json").read_text())
if not isinstance(manifest, dict) or not manifest:
    raise SystemExit("FPC SHA256.json must be a non-empty filename-to-hash object")
for name, expected in manifest.items():
    if Path(name).name != name or not name.startswith("fpcliu."):
        raise SystemExit(f"invalid FPC firmware manifest path: {name!r}")
    path = root / name
    if not path.is_file():
        raise SystemExit(f"FPC firmware manifest references missing file: {name}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != expected:
        raise SystemExit(f"FPC firmware SHA256 mismatch for {name}: {digest}")
actual = {path.name for path in root.glob("fpcliu.*") if path.is_file()}
if actual != set(manifest):
    raise SystemExit(f"FPC manifest/file set mismatch: files={sorted(actual)} manifest={sorted(manifest)}")
PY

  mkdir -p "$out/lib/firmware"
  install -m 0644 "$src"/fpcliu.* "$out/lib/firmware/"
  install -m 0644 "$src/SHA256.json" "$out/lib/firmware/SHA256.json"
''
