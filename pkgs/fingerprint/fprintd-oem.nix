# SPDX-License-Identifier: MIT
#
# fprintd 1.94.5 with the OEM adaptive-template persistence change.
#
# The OEM TOD driver requests an updated opaque database on a genuine match and
# hands it to fprintd through private qdata on the enrolled FpPrint.  fprintd
# must commit that replacement in its own file store *before* it reports
# VerifyStatus success, otherwise an adapted template could be dropped (or
# reported as verified after a failed write).  The change is the component's generated
# patch, which touches src/file_storage.c, src/file_storage.h and src/device.c;
# oem-update.inc carries the compare-and-replace implementation itself.
#
# Built against libfprint-tod (same override the nixpkgs fprintd-tod package
# uses) so the loaded TOD driver shares one libfprint ABI with the daemon.
#
# The upstream PAM module is unchanged and is NOT used for fingerprint login:
# the OEM credential input has its own pam.d/liuqin-fpc-enrol service and
# pam-input helper (see pkgs/fingerprint/liuqin-fpc-oem.nix).
{ fprintd
, libfprint-tod
, src
, python3
, glibBuild
, stdenv
, lib
}:

(fprintd.override {
  libfprint = libfprint-tod;
  # fprintd has python3 in nativeBuildInputs, and its meson configure RUNS
  # tests/unittest_inspector.py through patchShebangs' interpreter lookup.  In a
  # cross build that lookup would find the *target* python3, which the build
  # host cannot execute, so the helper must be rewritten to the build-host
  # interpreter.  Identical to python3 in a native build, so the native
  # derivation (and its cache entry) is unchanged.
  python3 = python3.pythonOnBuildForHost;
}).overrideAttrs (oldAttrs: {
  # Version stays 1.94.5 from the vendor pin recorded in SOURCE_LOCK.json.
  pname = "fprintd-oem";

  # meson's configure step runs gdbus-codegen (provided by glib) to generate
  # the D-Bus interface code.  In a cross build only nativeBuildInputs are on
  # PATH, while fprintd carries glib as a *target* build input, so the
  # build-host glib has to be added; native builds already have it, hence the
  # condition - it keeps the native derivation identical.
  nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ])
    ++ lib.optionals (stdenv.buildPlatform != stdenv.hostPlatform) [ glibBuild ];

  # `patch` fails loudly if the 1.94.5 anchors ever move, which is the point:
  # this file is a verbatim application of the reviewed upstream change.
  postPatch = (oldAttrs.postPatch or "") + ''
    patch -p1 --no-backup-if-mismatch \
      < ${src}/fprintd-oem/fprintd-oem-update.patch
    cp ${src}/fprintd-oem/oem-update.inc \
      src/oem-update.inc
  '';

  meta = (oldAttrs.meta or { }) // {
    description = "fprintd with OEM adaptive-template persistence for the Xiaomi Pad 6 Pro fingerprint stack";
  };
})
