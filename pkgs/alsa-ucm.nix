# SPDX-License-Identifier: MIT (this expression; see NOTICE for payloads)
#
# The device's UCM2 entry points, layered next to the upstream alsa-ucm-conf
# tree instead of overriding it.
#
# alsa-lib installs `$out/share/alsa/ucm2` as a symlink to the alsa-ucm-conf
# store path, so alsa-ucm-conf is a build input of alsa-lib: editing it changes
# alsa-lib's derivation and with it every audio consumer in the closure
# (pipewire, GStreamer, ffmpeg, GTK, ...), which takes the whole desktop off the
# binary cache.  Nothing builds against this package - the runtime reaches it
# through ALSA_CONFIG_UCM2 (see modules/liuqin/hardware.nix) - so it stays a
# leaf and the rest of the closure keeps its upstream hashes.
{ runCommand, alsa-ucm-conf }:

runCommand "liuqin-alsa-ucm-conf" { } ''
  mkdir -p $out/share/alsa
  # cp -a: the upstream tree wires its conf.d entries to the card directories
  # with ~150 relative symlinks, and they stay valid inside the copy.
  cp -a ${alsa-ucm-conf}/share/alsa/ucm2 $out/share/alsa/ucm2
  # The upstream tree is read-only in the store; the two files below need to
  # create their directories inside the copy.
  chmod -R u+w $out/share/alsa/ucm2
  install -Dm0644 ${../data/ucm2/Qualcomm/sm8450/Xiaomi-Pad-6-Pro/HiFi.conf} \
    $out/share/alsa/ucm2/Qualcomm/sm8450/Xiaomi-Pad-6-Pro/HiFi.conf
  install -Dm0644 ${../data/ucm2/conf.d/sm8450/Xiaomi-Pad-6-Pro.conf} \
    $out/share/alsa/ucm2/conf.d/sm8450/Xiaomi-Pad-6-Pro.conf
''
