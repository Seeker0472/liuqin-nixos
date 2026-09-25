# Fixed-output import of the stock ABL DTBO entry set, extracted from the
# operator's own device (liuqin-audit/evidence/dtbo). Not redistributable;
# regenerate from your own stock dump if yours differs. Not available from
# the downstream v0.1.0 release, so this archive has to stay in the tree
# (builtins.path). The sha256 pins the
# NAR of the archive like the requireFile inputs in pkgs/firmware.nix
# (`nix hash path data/stock-dtbo-entries.tar.zst`).
builtins.path {
  path = ./stock-dtbo-entries.tar.zst;
  name = "liuqin-stock-dtbo-entries";
  sha256 = "sha256-QDdcIPam8UKMqf+CIA0Q4kVT8RrC6cYKoXPhGCxnqJ8=";
}
