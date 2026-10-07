# SPDX-License-Identifier: MIT
#
# hexagonrpc at the pinned downstream commit, with the liuqin patch
# from pkgs/hexagonrpc/patches (source and patches are unchanged downstream
# work; see NOTICE).
{ lib
, stdenv
, fetchFromGitHub
, meson
, ninja
, pkg-config
, systemdLibs
}:

stdenv.mkDerivation {
  pname = "hexagonrpc";
  version = "0.5.0-g598b591";

  src = fetchFromGitHub {
    owner = "linux-msm";
    repo = "hexagonrpc";
    rev = "598b591ae9da6a6cfe2ca5ea78998019ca6395ea";
    hash = "sha256-wr5x5NR/QVY/dMqpykNAc+iXYjUePmUEI+kMhqllzIU=";
  };

  patches = [
    ./patches/0001-hexagonrpcd-implement-ssc-file-service.patch
  ];

  nativeBuildInputs = [ meson ninja pkg-config ];
  buildInputs = [ systemdLibs ];
}
