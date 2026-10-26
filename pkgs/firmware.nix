# SPDX-License-Identifier: MIT (expression; payloads are proprietary)
# Copy the complete, manifest-verified OS2.0.4 asset tree. The asset source is
# the separate liuqin-firmware-assets-OS2 repository; no downstream
# release image or runtime Nixpkgs firmware package is consumed here.
{ lib, runCommand, python3, firmwareAssets }:

runCommand "liuqin-firmware" {
  nativeBuildInputs = [ python3 ];
  meta = {
    description = "OS2.0.4 static firmware for Xiaomi Pad 6 Pro (liuqin)";
    license = lib.licenses.unfree;
  };
} ''
  set -eu
  source=${firmwareAssets}/assets/firmware
  src="$source/lib/firmware"
  test -d "$src"
  test -f "$source/SHA256SUMS"
  python3 - "${firmwareAssets}" <<'PYEOF'
import csv
import hashlib
from pathlib import Path
import sys

root = Path(sys.argv[1])
with (root / "MANIFEST.tsv").open(newline="") as stream:
    rows = list(csv.DictReader(stream, delimiter="\t"))
expected = {
    row["output"]: row["sha256"]
    for row in rows
    if row["output"].startswith("assets/firmware/")
}
firmware_root = root / "assets/firmware"
actual = {
    path.relative_to(root).as_posix()
    for path in firmware_root.rglob("*")
    if path.is_file()
}
if not expected or actual != set(expected):
    raise SystemExit(
        f"firmware asset manifest/file-set mismatch: expected={sorted(expected)} actual={sorted(actual)}"
    )
for relative, expected_hash in expected.items():
    digest = hashlib.sha256()
    with (root / relative).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    actual_hash = digest.hexdigest()
    if actual_hash != expected_hash:
        raise SystemExit(f"firmware asset SHA256 mismatch for {relative}: {actual_hash}")
PYEOF

  (
    cd "$src"
    sha256sum --quiet -c "$source/SHA256SUMS"
    find . -type f -printf '%P\n' | LC_ALL=C sort > "$TMPDIR/firmware-files"
    cut -c67- "$source/SHA256SUMS" | LC_ALL=C sort > "$TMPDIR/manifest-files"
    cmp "$TMPDIR/firmware-files" "$TMPDIR/manifest-files"
  )

  mkdir -p "$out/lib/firmware"
  cp -a "$src"/. "$out/lib/firmware/"
  fw="$out/lib/firmware"

  # The stock image stores the A730 zap shader as an MDT plus external .bNN
  # load segments. The extractor preserves the MDT bytes as a730_zap.mbn.
  # qcom_mdt_load() resolves every segment beside the DT-requested board path,
  # so project the complete set there; copying only the MDT fails on .b01.
  chmod u+w "$fw/qcom/sm8475/liuqin"
  for source_file in "$fw/qcom/a730_zap.mbn" "$fw"/qcom/a730_zap.b[0-9][0-9]; do
    test -f "$source_file"
    destination="$fw/qcom/sm8475/liuqin/$(basename "$source_file")"
    install -Dm0644 "$source_file" "$destination"
    cmp "$source_file" "$destination"
  done
  for required in \
    novatek/liuqin/novatek_nt36532_m81_fw_csot.bin \
    novatek/liuqin/novatek_nt36532_m81_fw_tm.bin \
    qcom/sm8475/liuqin/adsp.mbn \
    qcom/sm8475/liuqin/cdsp.mbn \
    qcom/sm8475/liuqin/slpi.mbn \
    qcom/a730_zap.mbn \
    qcom/sm8475/liuqin/a730_zap.mbn \
    qcom/a730_zap.b01 \
    qcom/sm8475/liuqin/a730_zap.b01 \
    qcom/a730_sqe.fw \
    qcom/gmu_gen70000.bin \
    qcom/vpu/vpu20_4v.mbn \
    qcom/sm8450/Xiaomi-Pad-6-Pro-tplg.bin \
    cirrus/cs35l41-dsp1-spk-prot.wmfw \
    cirrus/cs35l41-dsp1-spk-prot-10251826.wmfw \
    cirrus/cs35l41-dsp1-spk-prot-10251826-tl.bin \
    cirrus/cs35l41-dsp1-spk-prot-10251826-tr.bin \
    cirrus/cs35l41-dsp1-spk-prot-10251826-br.bin \
    cirrus/cs35l41-dsp1-spk-prot-10251826-bl.bin \
    qca/wcnhpbtfw21.tlv \
    qca/wcnhpnv21g.bin \
    regulatory.db \
    regulatory.db.p7s; do
    test -r "$fw/$required" || {
      echo "firmware missing: $required" >&2
      exit 1
    }
  done

  # Keep each ath11k board/firmware tuple intact. The plain paths win in the
  # custom firmware_class.path union; `updates/` remains available as the
  # source-layout copy. The compressed Nixpkgs set is only the fallback.
  for hw in hw2.0 hw2.1; do
    for file in amss.bin board-2.bin m3.bin regdb.bin; do
      test -r "$fw/ath11k/WCN6855/$hw/$file.zst"
      test -r "$fw/ath11k/WCN6855/$hw/$file"
      test -r "$fw/updates/ath11k/WCN6855/$hw/$file"
      cmp "$fw/ath11k/WCN6855/$hw/$file" \
          "$fw/updates/ath11k/WCN6855/$hw/$file"
    done
  done

  # Confirm that generated loader aliases preserve the official source bytes.
  for source_file in "$fw"/qca/hp*; do
    test -f "$source_file" || continue
    alias="$fw/qca/wcn$(basename "$source_file")"
    test -f "$alias"
    cmp "$source_file" "$alias"
  done
  cmp "$fw/cirrus/cs35l41-dsp1-spk-prot.wmfw" \
      "$fw/cirrus/cs35l41-dsp1-spk-prot-10251826.wmfw"
  for position in tl tr br bl; do
    case "$position" in
      tl) stock=TL ;; tr) stock=TR ;; br) stock=BR ;; bl) stock=BL ;;
    esac
    cmp "$fw/cirrus/$stock-cs35l41-dsp1-spk-prot.bin" \
        "$fw/cirrus/cs35l41-dsp1-spk-prot-10251826-$position.bin"
  done
''
