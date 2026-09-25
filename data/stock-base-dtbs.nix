# Fixed-output import of the stock ABL base DTB set (the DTBs the stock
# bootloader picks between). All 11 entries of vendor_boot.img's DTB table,
# extracted from the operator's own stock ROM dump; not redistributable.
# Not available from the downstream v0.1.0 release, which ships no
# vendor_boot.img, so this archive has to stay in the tree (builtins.path).
# This must stay the full set: pkgs/bootimg.nix seeds the ABL __symbols__
# union from every base DTB's __symbols__, and a base set that exports fewer
# labels makes ABL abort on the first fixup it cannot resolve (a single base
# DTB exports 1451 labels, the full set 1744). The sha256 pins the NAR of
# the archive so the store path is content-addressed like the requireFile
# inputs in pkgs/firmware.nix
# (`nix hash path data/stock-base-dtbs.tar.zst`).
builtins.path {
  path = ./stock-base-dtbs.tar.zst;
  name = "liuqin-stock-base-dtbs";
  sha256 = "sha256-lgxR1MldT3okWXaE4cL88xlmBaQDpIRygx8PYkcitEo=";
}
