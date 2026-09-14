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

  nativeBuildInputs = [ meson ninja pkg-config protobufc protobuf ];
  buildInputs = [ glib json-glib protobufc libqmi ];
}
