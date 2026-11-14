#!/usr/bin/env bash
set -euo pipefail
abl_research_dir=$(cd -- "$(dirname -- "$0")" && pwd)
exec nix shell --impure --expr 'let p = (builtins.getFlake "nixpkgs").legacyPackages.x86_64-linux; in p.python3.withPackages (ps: [ ps.pefile ps.unicorn ])' --command python3 "$abl_research_dir/emulate_name_match.py"
