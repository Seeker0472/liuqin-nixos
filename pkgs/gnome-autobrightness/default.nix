# SPDX-License-Identifier: MIT
#
# The Automatic Brightness Quick Settings extension for the Xiaomi Pad 6 Pro:
# one tile that toggles gnome-settings-daemon's ambient-brightness switch and
# shows the lux reading driving it.
#
# The icon is the Material Design Icons "brightness-auto" glyph (the same
# artwork the Nerd Font's U+F00E1 codepoint carries), taken from
# github.com/Templarian/MaterialDesign and used under the Pictogrammers Free
# License (see LICENSE-materialdesign).  It is installed as a *-symbolic name
# so the shell recolours it from the icon's alpha channel, like its own icons.
{ stdenv }:

stdenv.mkDerivation {
  pname = "liuqin-gnome-autobrightness";
  version = "1";

  src = ./.;

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    uuid=liuqin-autobrightness@liuqin
    mkdir -p $out/share/gnome-shell/extensions/$uuid
    install -m 0644 metadata.json extension.js $out/share/gnome-shell/extensions/$uuid/
    install -m 0644 LICENSE-materialdesign $out/share/gnome-shell/extensions/$uuid/

    mkdir -p $out/share/icons/hicolor/scalable/status
    install -m 0644 auto-brightness-symbolic.svg \
      $out/share/icons/hicolor/scalable/status/auto-brightness-symbolic.svg

    runHook postInstall
  '';

  meta = {
    description = "Automatic-brightness toggle for Quick Settings";
    platforms = [ "aarch64-linux" "x86_64-linux" ];
  };
}
