# SPDX-License-Identifier: MIT
{ lib, stdenvNoCC, makeWrapper, python3, glib, dconf, dbus, gnome-control-center }:
let
  runtime = python3.withPackages (ps: [ ps.pygobject3 ps.evdev ]);
in
stdenvNoCC.mkDerivation {
  pname = "liuqin-power-keyd";
  version = "2.0.0";
  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: type: type == "directory" || builtins.elem (baseNameOf path) [
      "broker.py" "launch.py" "session.py" "policy.py" "transport.py" "liuqin-power-menu.py"
      "test_policy.py" "test_dbus.py" "test_transport.py" "test_broker.py"
    ];
  };
  nativeBuildInputs = [ makeWrapper runtime glib dbus ];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    export PYTHONDONTWRITEBYTECODE=1
    export GI_TYPELIB_PATH=${glib.out}/lib/girepository-1.0
    export GSETTINGS_BACKEND=memory
    python3 -m unittest discover -v -p 'test_*.py'
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/liuqin-power $out/bin
    cp broker.py launch.py session.py policy.py transport.py $out/libexec/liuqin-power/
    install -m755 liuqin-power-menu.py $out/libexec/liuqin-power-menu
    substituteInPlace $out/libexec/liuqin-power-menu \
      --replace-fail '#!/usr/bin/env python3' '#!${python3}/bin/python3' \
      --replace-fail '/usr/share/locale' '${gnome-control-center}/share/locale'
    makeWrapper ${runtime}/bin/python3 $out/bin/liuqin-power-session \
      --add-flags "$out/libexec/liuqin-power/launch.py" \
      --prefix GI_TYPELIB_PATH : ${glib.out}/lib/girepository-1.0 \
      --prefix GIO_EXTRA_MODULES : ${dconf.lib}/lib/gio/modules \
      --set LIUQIN_POWER_MENU $out/libexec/liuqin-power-menu
    makeWrapper ${runtime}/bin/python3 $out/bin/liuqin-power-keyd \
      --add-flags "$out/libexec/liuqin-power/broker.py --session-program $out/bin/liuqin-power-session" \
      --prefix GI_TYPELIB_PATH : ${glib.out}/lib/girepository-1.0
    runHook postInstall
  '';
}
