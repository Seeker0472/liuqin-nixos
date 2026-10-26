# SPDX-License-Identifier: MIT
#
# Keyboard Backlight Quick Settings extension for the Xiaomi Pad 6 Pro: a
# toggle and brightness slider backed by UPower's standard KbdBacklight API.
{ stdenv }:

stdenv.mkDerivation {
  pname = "liuqin-gnome-keyboard-backlight";
  version = "1";

  src = ./.;

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    uuid=liuqin-keyboard-backlight@liuqin
    mkdir -p $out/share/gnome-shell/extensions/$uuid
    install -m 0644 metadata.json extension.js $out/share/gnome-shell/extensions/$uuid/

    runHook postInstall
  '';

  meta = {
    description = "Keyboard-backlight toggle and brightness slider for Quick Settings";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
