# SPDX-License-Identifier: MIT
#
# AP-side MiPPS coordinator.  The daemon intentionally has no key material in
# the derivation; keys are provisioned into /var/lib/liuqin/mipps at runtime.
{ stdenv
, openssl
}:

stdenv.mkDerivation {
  pname = "liuqin-mippsd";
  version = "0.1.0";
  src = ./mipps-daemon.c;
  dontUnpack = true;
  buildPhase = ''
    $CC -std=c11 -O2 -Wall -Wextra -Werror \
      -I${openssl.dev}/include -L${openssl.out}/lib \
      -Wl,-rpath,${openssl.out}/lib \
      -o liuqin-mippsd $src -lcrypto
  '';
  installPhase = ''
    install -Dm0755 liuqin-mippsd $out/bin/liuqin-mippsd
  '';
  meta.description = "Root-only Xiaomi MiPPS authentication coordinator for liuqin";
}
