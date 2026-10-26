# SPDX-License-Identifier: MIT
{ lib, runCommand, zip, python3 }:

let
  version = "1.0.0";
in
runCommand "liuqin-return-to-uboot-ksu-${version}"
  {
    src = ./.;
    nativeBuildInputs = [ zip python3 ];
    meta = {
      description = "KernelSU module selecting the liuqin U-Boot slot after Android boot";
      platforms = lib.platforms.linux;
    };
  }
  ''
    python3 "$src/test_module.py"
    grep -Fx 'version=${version}' "$src/module.prop"
    test -x "$src/boot-completed.sh"
    mkdir -p "$out" module
    cp "$src/module.prop" "$src/boot-completed.sh" "$src/skip_mount" module/
    chmod 0755 module/boot-completed.sh
    # ZIP stores member timestamps; pin them so rebuilds produce the same ZIP.
    touch -d '1980-01-01 00:00:00 UTC' module/*
    cd module
    zip -X -q "$out/liuqin-return-to-uboot-${version}.zip" \
      module.prop boot-completed.sh skip_mount
  ''
