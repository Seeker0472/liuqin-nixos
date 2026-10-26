# SPDX-License-Identifier: MIT
# A typed session client: preserve extended layouts while rotating DSI-1.
{
  stdenvNoCC,
  python3,
  glib,
  gnome-settings-daemon,
  makeWrapper,
}:
let
  python = python3.withPackages (ps: [ ps.pygobject3 ]);
in
stdenvNoCC.mkDerivation {
  pname = "liuqin-panel-posture";
  version = "2";
  src = ./panel-posture;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    export GSETTINGS_BACKEND=memory
    export XDG_DATA_DIRS=${gnome-settings-daemon}/share/gsettings-schemas/${gnome-settings-daemon.name}
    ${python}/bin/python3 -m unittest discover -v
  '';
  installPhase = ''
    mkdir -p $out/libexec/liuqin-panel-posture $out/bin
    cp main.py layout.py $out/libexec/liuqin-panel-posture/
    makeWrapper ${python}/bin/python3 $out/bin/liuqin-panel-posture \
      --add-flags "$out/libexec/liuqin-panel-posture/main.py" \
      --prefix GI_TYPELIB_PATH : ${glib.out}/lib/girepository-1.0 \
      --prefix XDG_DATA_DIRS : ${gnome-settings-daemon}/share/gsettings-schemas/${gnome-settings-daemon.name}
  '';
}
