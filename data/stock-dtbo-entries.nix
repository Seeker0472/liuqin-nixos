# Fixed-output import of the stock ABL DTBO entry set, extracted from the
# operator's own device (liuqin-audit/evidence/dtbo). Not redistributable;
# regenerate from your own stock dump if yours differs.
builtins.path {
  path = ./stock-dtbo-entries.tar.zst;
  name = "liuqin-stock-dtbo-entries";
}
