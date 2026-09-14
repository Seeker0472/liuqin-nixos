# SPDX-License-Identifier: MIT
#
# liuqin-power-keyd package: the C daemon plus its session-side helpers.
# Sources copied from the downstream project (MIT). Helpers are installed
# under $out/libexec and wired to Nix store tools by the NixOS module's
# systemd environment.
{ lib
, stdenv
, python3
, zenity
, gnome-session
}:

stdenv.mkDerivation {
  pname = "liuqin-power-keyd";
  version = "1.0.0";

  src = ./liuqin-power-keyd;

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
      --replace-fail '#!/usr/bin/env python3' '#!${python3}/bin/python3'
    runHook postInstall
  '';

  passthru.sessionPath = lib.makeSearchPath "bin" [
    zenity
    gnome-session
  ];
}
