# SPDX-License-Identifier: MIT
# GNOME session client for the liuqin folio lid policy.
{
  stdenvNoCC,
  python3,
  glib,
  makeWrapper,
}:
let
  python = python3.withPackages (ps: [ ps.pygobject3 ]);
in
stdenvNoCC.mkDerivation {
  pname = "liuqin-lid-policy";
  version = "1";
  src = ./lid-policy;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    ${python}/bin/python3 -m unittest discover -v
  '';
  installPhase = ''
    mkdir -p $out/libexec/liuqin-lid-policy $out/bin
    cp main.py $out/libexec/liuqin-lid-policy/
    makeWrapper ${python}/bin/python3 $out/bin/liuqin-lid-policy \
      --add-flags "$out/libexec/liuqin-lid-policy/main.py" \
      --prefix GI_TYPELIB_PATH : ${glib.out}/lib/girepository-1.0
  '';
}
