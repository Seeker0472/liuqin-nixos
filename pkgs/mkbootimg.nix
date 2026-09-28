# SPDX-License-Identifier: MIT
#
# AOSP mkbootimg.py at a pinned commit (same source and hashes as the
# downstream project's tools/fetch-aosp-mkbootimg.sh, android-16.0.0_r4).
{ lib, stdenvNoCC, fetchgit, python3 }:

let
  commit = "954bc3ead5e679005fddf3484d247f2557b3c2c9";
in
stdenvNoCC.mkDerivation {
  pname = "aosp-mkbootimg";
  version = "android-16.0.0_r4-${lib.substring 0 12 commit}";

  # gitiles regenerates the +archive tarball server-side, so its bytes - and
  # therefore a plain fetchurl hash - are not stable: three different digests
  # have been observed for this same commit. Pin the git checkout instead (the
  # revision fixes the content) and keep the per-file digests asserted in
  # installPhase as the content contract.
  src = fetchgit {
    url = "https://android.googlesource.com/platform/system/tools/mkbootimg";
    rev = commit;
    hash = "sha256-Mt42IF+xZcb9KZxuCGOWODE4kDI1wYsJLXKiimiBieQ=";
  };

  nativeBuildInputs = [ python3 ];

  installPhase = ''
    runHook preInstall
    # Pin the exact files the downstream fetch script verified.
    echo '37d84b3d162e0bc62e36c1f4e1c63c85ea0caa9f29be023eb2f8efe006ad948c  mkbootimg.py' | sha256sum -c --quiet
    echo '06b54dd9a07c5281778e29e234e76f6e3faee8bf0c904a5ef88fdee30eeed12e  unpack_bootimg.py' | sha256sum -c --quiet
    install -Dm0755 mkbootimg.py $out/bin/mkbootimg.py
    ln -s mkbootimg.py $out/bin/mkbootimg
    install -Dm0755 unpack_bootimg.py $out/bin/unpack_bootimg.py
    # mkbootimg imports the in-tree gki/ module at runtime; the gki
    # testdata/ subdirectory ships test-only private keys (avb test keys),
    # which must not be present on the device closure.
    cp -r gki $out/bin/
    rm -rf $out/bin/gki/testdata
    substituteInPlace $out/bin/mkbootimg.py --replace-fail '#!/usr/bin/env python3' '#!${python3}/bin/python3'
    substituteInPlace $out/bin/unpack_bootimg.py --replace-fail '#!/usr/bin/env python3' '#!${python3}/bin/python3'
    runHook postInstall
  '';
}
