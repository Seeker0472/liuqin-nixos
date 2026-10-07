# SPDX-License-Identifier: MIT
#
# The Flashlight Quick Settings extension for the Xiaomi Pad 6 Pro: a toggle
# and a brightness slider for the rear flash LED (white:flash).
#
# The two icons are the Material Design Icons "flashlight" and
# "flashlight-off" glyphs (the same artwork the Nerd Font's U+F0244/U+F0245
# codepoints carry), taken from github.com/Templarian/MaterialDesign and used
# under the Pictogrammers Free License (see LICENSE-materialdesign).  They are
# installed as *-symbolic names so the shell recolours them from the icon's
# alpha channel, like its own icons.
{ stdenv }:

stdenv.mkDerivation {
  pname = "liuqin-gnome-flashlight";
  version = "1";

  src = ./.;

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    uuid=liuqin-flashlight@liuqin
    mkdir -p $out/share/gnome-shell/extensions/$uuid
    install -m 0644 metadata.json extension.js $out/share/gnome-shell/extensions/$uuid/
    install -m 0644 LICENSE-materialdesign $out/share/gnome-shell/extensions/$uuid/

    mkdir -p $out/share/icons/hicolor/scalable/status
    install -m 0644 flashlight-symbolic.svg \
      $out/share/icons/hicolor/scalable/status/flashlight-symbolic.svg
    install -m 0644 flashlight-off-symbolic.svg \
      $out/share/icons/hicolor/scalable/status/flashlight-off-symbolic.svg

    runHook postInstall
  '';

  meta = {
    description = "Flashlight toggle and brightness slider for Quick Settings";
    platforms = [ "aarch64-linux" "x86_64-linux" ];
  };
}
