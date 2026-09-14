# Fixed-output import of the stock ABL base DTB set (the DTBs the stock
# bootloader picks between). Extracted from the operator's own stock boot
# image; not redistributable.
builtins.path {
  path = ./stock-base-dtbs.tar.zst;
  name = "liuqin-stock-base-dtbs";
}
