# SPDX-License-Identifier: MIT
#
# pam_liuqin_fpc.so - credential input preparation for the OEM FPC1264 stack.
#
# The trustlet accepts a template only when the enrolment is authorised with the
# account's credential input (PBKDF2-HMAC-SHA256 over the Linux password).
# fprintd's Enroll API cannot carry a secret, so this module derives and caches
# it whenever the account authenticates with its password, using exactly the
# custody the OEM bundle's acceptance_input.prepare() defines (root UID keyring,
# 18 h expiry, one use, boot-local, nothing on disk).  The TOD driver's
# enroll() then runs the trustlet without a second prompt.
#
# See pam-liuqin-fpc.c for the full contract; modules/liuqin/fingerprint.nix
# places the module in the password authentication stacks.
{ lib
, stdenv
, pam
, openssl
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "pam-liuqin-fpc";
  version = "0.1.0";

  # A single translation unit; no unpack step.
  src = ./pam-liuqin-fpc.c;

  dontUnpack = true;

  buildInputs = [
    pam
    openssl
  ];

  buildPhase = ''
    runHook preBuild
    $CC -O2 -std=c11 -Wall -Wextra -Werror -fPIC -shared \
      -o pam_liuqin_fpc.so $src -lpam -lcrypto
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 pam_liuqin_fpc.so $out/lib/security/pam_liuqin_fpc.so
    runHook postInstall
  '';

  meta = {
    description = "PAM module preparing the FPC1264 credential input at password authentication";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
})
