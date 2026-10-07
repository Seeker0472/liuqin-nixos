# SPDX-License-Identifier: MIT
#
# liuqin-power-keyd package: the C daemon plus its session-side helpers.
# Sources copied from the downstream project (MIT). Helpers are installed
# under $out/libexec and wired to Nix store tools by the NixOS module's
# systemd environment.
{ lib
, stdenv
, coreutils
, python3
, gnome-control-center
}:

stdenv.mkDerivation {
  pname = "liuqin-power-keyd";
  version = "1.0.0";

  # The daemon's own sources are the three files next to this expression;
  # this file and the gschema (installed by modules/liuqin/gnome.nix) are
  # filtered out so src carries exactly them.
  src = builtins.path {
    path = ./.;
    name = "liuqin-power-keyd";
    filter =
      path: type:
      !(builtins.elem (builtins.baseNameOf path)
        [ "default.nix" "io.github.liuqin.power.gschema.xml" ]);
  };

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    $CC -std=c11 -O2 -Wall -Wextra \
      -DDEFAULT_ACTION_HELPER="\"$out/libexec/liuqin-power-key-action\"" \
      -o liuqin-power-keyd liuqin-power-keyd.c
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm0755 liuqin-power-keyd $out/libexec/liuqin-power-keyd
    install -Dm0755 liuqin-power-key-action.sh $out/libexec/liuqin-power-key-action
    install -Dm0755 liuqin-power-menu.py $out/libexec/liuqin-power-menu
    substituteInPlace $out/libexec/liuqin-power-menu \
      --replace-fail '#!/usr/bin/env python3' '#!${python3}/bin/python3' \
      --replace-fail '/usr/share/locale' '${gnome-control-center}/share/locale'
    # No /usr/bin or /usr/sbin on NixOS: the helper must call coreutils'
    # test(1) by absolute path (it runs via setpriv, not a shell builtin).
    substituteInPlace $out/libexec/liuqin-power-key-action \
      --replace-fail '"$test_bin" -S' '"${coreutils}/bin/test" -S'
    runHook postInstall
  '';
}
