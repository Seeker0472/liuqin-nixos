# Fixed-output import of the stock ABL base DTB set (the DTBs the stock
# bootloader picks between). All 11 entries of vendor_boot.img's DTB table,
# extracted from the operator's own stock ROM dump; not redistributable, so
# the archive is operator-supplied and neither committed nor shipped in the
# flake source - register it once and the build reuses the store copy:
#
#   nix-store --add-fixed sha256 stock-base-dtbs.tar.zst
#   # or point hardware/system config at your own dump and rebuild the archive
#
# This must stay the full set: pkgs/bootimg/default.nix seeds the ABL __symbols__
# union from every base DTB's __symbols__, and a base set that exports fewer
# labels makes ABL abort on the first fixup it cannot resolve (a single base
# DTB exports 1451 labels, the full set 1744).
{ requireFile }:

requireFile {
  name = "stock-base-dtbs.tar.zst";
  hash = "sha256-xbsmCX9Npga3wwyVHmiplwqY+pHnUxwS3F9H7Yqe19k=";
  message = ''
    The stock ABL base DTB set (11 DTBs) from this device's vendor_boot.img,
    packed as a zstd tar archive with dtb-*.dtb members. Extract it from your
    own stock ROM dump and add it to the store with
    `nix-store --add-fixed sha256 stock-base-dtbs.tar.zst` (the name must be
    this file's exact basename; keep the archive next to this file, where
    .gitignore keeps it untracked).
    The downstream release ships no vendor_boot.img, so this cannot be fetched.
  '';
}
