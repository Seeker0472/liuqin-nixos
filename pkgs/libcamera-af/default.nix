# SPDX-License-Identifier: MIT
#
# The patched libcamera of the liuqin AF series: the local patches of
# this directory (upstream-bound; see README.md) plus the per-sensor soft-IPA
# tuning files.
#
# Built as a standalone package rather than an override of the closure's
# libcamera: replacing that would rebuild pipewire -> mutter -> GNOME (~142
# derivations).  `hardware.liuqin.camera.autofocus.enable` injects this build
# into the two GNOME processes that run libcamera (pipewire, wireplumber) with
# LD_LIBRARY_PATH; same soname, same version, patches confined to the simple
# pipeline and its IPA.
{ libcamera }:
libcamera.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ./0001-swisp-focus-stat.patch
    ./0002-ipa-simple-lens-control.patch
    ./0003-ipa-simple-agc.patch
    ./0004-ipa-simple-awb.patch
    ./0005-ipa-simple-af.patch
    ./0006-ipa-simple-adjust.patch
    ./0007-sensor-helpers.patch
    ./0008-camera-sensor-flip-defaults.patch
  ];

  # Per-sensor simple-IPA tuning files: without them the soft ISP logs
  # "Configuration file '<model>.yaml' not found ... falling back to
  # uncalibrated.yaml" on every camera.
  postInstall = (old.postInstall or "") + ''
    for s in liuqin-camera-sensors; do
      cp $out/share/libcamera/ipa/simple/uncalibrated.yaml \
         $out/share/libcamera/ipa/simple/$s.yaml
    done
    install -m 0644 ${./tuning/s5kjn1.yaml} $out/share/libcamera/ipa/simple/s5kjn1.yaml
    install -m 0644 ${./tuning/imx596.yaml} $out/share/libcamera/ipa/simple/imx596.yaml
    install -m 0644 ${./tuning/sc202cs.yaml} $out/share/libcamera/ipa/simple/sc202cs.yaml
  '';
})
