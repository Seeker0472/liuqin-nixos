# SPDX-License-Identifier: MIT
#
# libssc (Qualcomm SSC QMI client library + ssccli) at the pinned downstream
# commit.
{ lib
, stdenv
, fetchFromCodeberg
, meson
, ninja
, pkg-config
, glib
, json-glib
, protobufc
, protobuf
, libqmi
, python3
, python3Packages
, qrtr
}:

stdenv.mkDerivation {
  pname = "libssc";
  version = "0.4.4";

  src = fetchFromCodeberg {
    owner = "DylanVanAssche";
    repo = "libssc";
    rev = "0cf77b93b55752da34dca2dcecc06fca8665184b";
    hash = "sha256-C9A0NtkGztSJQIkv4diGAPhZMUiIUszRNYif2yZL8nI=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    protobufc
    protobuf
    python3
    python3Packages.pygobject3
    python3Packages.protobuf
  ];
  buildInputs = [ glib json-glib protobufc libqmi ];

  # The upstream custom target lists the configured ssc-server as one of the
  # files copied by `cp`; that target only copies qmi.py and ssc.py and causes
  # Meson to hide the configured wrapper. Keep the generated wrapper visible
  # to the test harness.  Inject the pinned raw QRTR library into its search
  # path because Nix stores it outside /usr/lib.
  postPatch = ''
    substituteInPlace mocking/ssc_server/meson.build \
      --replace-fail "output: ['qmi.py', 'ssc.py', 'ssc-server', 'ssc-server-tests']" \
                    "output: ['qmi.py', 'ssc.py']"
    substituteInPlace mocking/ssc_server/ssc-server.in \
      --replace-fail '#!/usr/bin/env python3' '#!${python3}/bin/python3' \
      --replace-fail "for path in [" \
                    "for path in [ '${qrtr}/lib/libqrtr.so.1',"
  '';

  # The service suite needs AF_QIPCRTR and a raw QRTR socket.  The pinned
  # liuqinQrtr library makes that dependency explicit; builders whose kernel
  # lacks AF_QIPCRTR report those Meson cases as skips (the upstream harness
  # uses exit 77), while a capable builder exercises the parser paths.
  doCheck = true;
}
