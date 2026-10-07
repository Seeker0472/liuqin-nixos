# Fixed-output import of the stock ABL DTBO entry set, extracted from the
# operator's own device (liuqin-audit/evidence/dtbo). Not redistributable, so
# the archive is operator-supplied and neither committed nor shipped in the
# flake source - register it once and the build reuses the store copy:
#
#   nix-store --add-fixed sha256 stock-dtbo-entries.tar.zst
#
# Regenerate it from your own stock dump if your unit's entries differ; the
# downstream release ships no such archive.
{ requireFile }:

requireFile {
  name = "stock-dtbo-entries.tar.zst";
  hash = "sha256-kDPwvA/Y6PEsRfZk8aZ9sHbtVli8cN8Djnyxuj7SUKY=";
  message = ''
    The stock ABL DTBO entry set (entry.*.dtb members) from this device's
    stock vendor_boot/dtbo images, packed as a zstd tar archive. Extract it
    from your own stock dump and add it to the store with
    `nix-store --add-fixed sha256 stock-dtbo-entries.tar.zst` (this exact
    basename; keep the archive next to this file).
  '';
}
