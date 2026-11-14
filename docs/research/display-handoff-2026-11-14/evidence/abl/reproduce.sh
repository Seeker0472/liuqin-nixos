#!/usr/bin/env bash
set -euo pipefail
abl_research_dir=$(cd -- "$(dirname -- "$0")" && pwd)
exec nix shell --impure --expr 'let p = (builtins.getFlake "nixpkgs").legacyPackages.x86_64-linux; in p.python3.withPackages (ps: [ ps.capstone ps.pefile ps.pyelftools ps.uefi-firmware ])' --command python3 "$abl_research_dir/reproduce.py"
