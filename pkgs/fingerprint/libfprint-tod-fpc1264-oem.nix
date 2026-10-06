# SPDX-License-Identifier: MIT
#
# FPC1264 OEM Touch-OEM-Driver for libfprint-tod.
#
# The driver is an out-of-tree libfprint TOD module: it registers the virtual
# `fpc1264_oem` device (selected with FP_LIUQIN_FPC1264_OEM_ENABLE=1 and
# FP_DRIVERS_ALLOWLIST=fpc1264_oem) and implements one verification path.  It
# owns no matching logic: verify() serializes the single stored FpPrint into a
# private staging directory and runs the OEM runtime
# (LIUQIN_FPC_OEM_RUNTIME/oem_runtime.py), which talks to the FPC trusted
# application through /dev/fpc1020 and the TEE listeners.
#
# Built against libfprint-tod, exactly like the goodix TOD driver package
# (pkgs/by-name/li/libfprint-2-tod1-goodix) is installed: .so under
# $out/lib/libfprint-2/tod-1 and passthru.driverPath telling the NixOS fprintd
# module where FP_TOD_DRIVERS_DIR must point.  fpc-oem-print (the FpPrint
# serializer used by the authenticated enrolment path) ships here too and is
# copied into the runtime bundle by pkgs/fingerprint/liuqin-fpc-oem.nix.
{ lib
, stdenv
, src
, pkg-config
, patchelf
, libfprint-tod
, glib
, gusb
, python3
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "libfprint-tod-fpc1264-oem";
  version = "0-unstable-2026-10-02";

  inherit src;

  nativeBuildInputs = [
    pkg-config
    patchelf
  ];

  buildInputs = [
    libfprint-tod
    glib
    gusb
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    tod=$src/device/fingerprint/oem/src/fingerprint/libfprint-tod

    mkdir -p build

    # NixOS adaptation of the pinned source: the TOD driver spawns the OEM runner
    # as "/usr/bin/python3", a path that does not exist on NixOS.  Bake the
    # interpreter of the target package set in instead of adding a runtime knob;
    # the rest of the component's contract (LIUQIN_FPC_OEM_RUNTIME must be an absolute,
    # root-owned, non-writable directory) is unchanged.
    cp $tod/fpc1264-oem.c build/fpc1264-oem.c
    # NixOS adaptation: enrolment from the desktop.  The credential input is
    # prepared by pam_liuqin_fpc at password authentication (root keyring, one
    # use); the patch implements the driver's enroll() that consumes it through
    # user_credentials.py --enrol-prepared, translating the trustlet's progress
    # lines into libfprint progress/retry signals and returning the opaque
    # single-finger database as the enrolled FpPrint for fprintd to store.
    patch -p1 -d build < ${./fpc1264-oem-enroll.patch}
    grep -qF 'user_credentials.py", NULL' build/fpc1264-oem.c || {
      echo "libfprint-tod-fpc1264-oem: enrolment patch did not apply" >&2
      exit 1
    }
    grep -qF 'nr_enroll_stages = LIUQIN_ENROL_MAX_STAGES' build/fpc1264-oem.c || {
      echo "libfprint-tod-fpc1264-oem: enrolment stage declaration is missing" >&2
      exit 1
    }
    substituteInPlace build/fpc1264-oem.c \
      --replace-fail '"/usr/bin/python3"' '"${python3}/bin/python3"'
    grep -qF '"${python3}/bin/python3"' build/fpc1264-oem.c || {
      echo "libfprint-tod-fpc1264-oem: interpreter path was not rewritten" >&2
      exit 1
    }

    # cflags: libfprint-2 is named separately because the private headers
    # (fpi-device.h -> "fp-device.h") live in include/libfprint-2, which the
    # tod-1 .pc only pulls in through Requires.private.  gusb is named for the
    # same reason: fpi-device.h includes <gusb.h>, which lives in
    # include/gusb-1, and the plain include dir of the input is not enough.
    # $PKG_CONFIG, not `pkg-config`: in a cross build only the target-prefixed
    # wrapper (aarch64-unknown-linux-gnu-pkg-config) is on PATH.
    $CC -shared -fPIC -O2 -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror \
      $($PKG_CONFIG --cflags libfprint-2-tod-1 libfprint-2 gio-2.0 gusb) \
      build/fpc1264-oem.c \
      -o build/libfprint-tod-fpc1264-oem.so \
      $($PKG_CONFIG --libs libfprint-2-tod-1 gio-2.0)

    $CC -O2 -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror \
      $($PKG_CONFIG --cflags libfprint-2 libfprint-2-tod-1) \
      $tod/fpc-oem-print.c \
      -o build/fpc-oem-print \
      $($PKG_CONFIG --libs libfprint-2 libfprint-2-tod-1)
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    tod=$src/device/fingerprint/oem/src/fingerprint/libfprint-tod

    install -Dm755 build/libfprint-tod-fpc1264-oem.so \
      $out/lib/libfprint-2/tod-1/libfprint-tod-fpc1264-oem.so
    install -Dm755 build/fpc-oem-print $out/bin/fpc-oem-print
    # The component's candidate drop-in, kept for reference: the NixOS module
    # (modules/liuqin/fingerprint.nix) expresses the same settings natively.
    install -Dm644 $tod/fprintd-fpc1264-oem.conf \
      $out/share/libfprint-tod-fpc1264-oem/fprintd-fpc1264-oem.conf
    runHook postInstall
  '';

  # The driver resolves fpi_* / fp_print_* from the libfprint-tod it was built
  # against; give the module an rpath so it loads even if the process happens
  # not to have that exact library mapped already.
  postFixup = ''
    patchelf --set-rpath ${lib.makeLibraryPath [ libfprint-tod ]} \
      $out/lib/libfprint-2/tod-1/libfprint-tod-fpc1264-oem.so
  '';

  # Consumed by services.fprintd.tod.driver in modules/liuqin/fingerprint.nix
  # (and by the nixpkgs fprintd module, which builds FP_TOD_DRIVERS_DIR from
  # it).  Same value as pkgs.libfprint-2-tod1-goodix.
  passthru.driverPath = "/lib/libfprint-2/tod-1";

  meta = {
    description = "FPC1264 OEM fingerprint driver (libfprint TOD) for the Xiaomi Pad 6 Pro";
    homepage = "https://github.com/yuzelingsha/xiaomipad-6pro-mainline";
    license = with lib.licenses; [ lgpl21Plus ];
    platforms = lib.platforms.linux;
  };
})
