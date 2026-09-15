# Fixed-output import of the stock ABL base DTB set (the DTBs the stock
# bootloader picks between). Extracted from the operator's own stock boot
# image; not redistributable. The sha256 pins the NAR of the archive so the
# store path is content-addressed like the requireFile inputs in
# pkgs/firmware.nix (`nix hash path data/stock-base-dtbs.tar.zst`).
builtins.path {
  path = ./stock-base-dtbs.tar.zst;
  name = "liuqin-stock-base-dtbs";
  sha256 = "sha256-AhXJP206N7Rrqvscb0heLd3XwA3tBfwIAHV+R8F7C1Q=";
}
