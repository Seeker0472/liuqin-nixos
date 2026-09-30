# SPDX-License-Identifier: BSD-3-Clause
#
# The libssc host-side mock server uses the small raw QRTR C library.  The
# nixpkgs qrtr package is the Qualcomm IDL compiler and is ARM-only; keep this
# separately pinned library package available for the x86_64 test harness too.
{ lib
, stdenv
, fetchFromGitHub
, meson
, ninja
, pkg-config
}:

stdenv.mkDerivation {
  pname = "liuqin-qrtr";
  version = "1.2-unstable-2026-09-29";

  src = fetchFromGitHub {
    owner = "linux-msm";
    repo = "qrtr";
    rev = "29e36ae164389580a0f8ea7a7fdb728140ae978d";
    hash = "sha256-XVHnF6EpOLpsKCNV8O1wHw67aeiBEqolGCV4N2Vo5W0=";
  };

  nativeBuildInputs = [ meson ninja pkg-config ];

  meta = {
    description = "Qualcomm QRTR userspace library used by the SSC test harness";
    homepage = "https://github.com/linux-msm/qrtr";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
}
