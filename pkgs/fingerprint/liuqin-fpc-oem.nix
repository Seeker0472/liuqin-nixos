# SPDX-License-Identifier: MIT
#
# OEM FPC1264 userspace runtime for the Xiaomi Pad 6 Pro (liuqin, SM8475).
#
# This is the trust anchor of the fingerprint stack: the static diagnostic /
# credential clients (fpc_build_info, qsee-gatekeeper), the QSEE TEE
# supplicant that serves the FS/GPFS/RPMB listeners, the authenticated UFS
# RPMB provider, the PAM credential input helper and the Python entry points
# that drive one operation at a time (oem_runtime.py and friends).
#
# Everything is installed into ONE flat prefix, $out/libexec/liuqin-fpc-oem,
# because the Python entry points resolve their own siblings through
# Path(__file__).parent (authorize_oem.py -> fpc_build_info/qsee-gatekeeper,
# oem_runtime.py -> qsee-supplicant + ufs-rpmb-provider/... + the clients,
# enrol_publish.py -> fpc-oem-print, user_credentials.py -> pam-input).  That
# prefix is exactly what the TOD driver and the NixOS module pass as
# LIUQIN_FPC_OEM_RUNTIME, and the driver additionally requires it to be an
# absolute, root-owned directory that is not group/other writable - a store
# path satisfies that without any /usr/local installation step.
#
# Compile commands follow the component's tools/build-userspace.sh at the
# pinned revision: the clients are static so they cannot pick up a host
# libc, pam-input is a normal dynamic binary because it must use the system
# PAM stack, and QCBOR is the vendored 1.6.1 source subset.
{ lib
, stdenv
, src
, qcbor
, supplicant
, python3
, pam
, openssl
, todDriver
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "liuqin-fpc-oem";
  version = "0-unstable-2026-10-02";

  inherit src;

  buildInputs = [
    pam
    openssl
    # The runtime interpreter whose path is baked into the shebangs below; it
    # is also the interpreter the TOD driver spawns (see
    # pkgs/fingerprint/libfprint-tod-fpc1264-oem.nix).
    python3
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    client=$src/oem
    vendor=${supplicant}
    qcbor=${qcbor}

    mkdir -p build/clients/ufs-rpmb-provider

    # glibc keeps libc.a/libm.a in a separate output, and the cc-wrapper only
    # puts the shared one on the search path (a `-static` client would fail
    # with "cannot find -lc").  Add it as a link argument for the static
    # clients only: putting it in buildInputs would put libc.a first on the
    # search path of pam-input as well and turn that dynamic link into a
    # half-static one ("DSO missing from command line").
    staticLibc=${stdenv.cc.libc.static}/lib
    flags=(-static -L$staticLibc -O2 -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror)

    $CC "''${flags[@]}" -o build/clients/fpc_build_info $client/fpc_build_info.c
    $CC "''${flags[@]}" -I$qcbor/inc -o build/clients/qsee-gatekeeper \
      $client/qsee_gatekeeper.c $qcbor/src/qcbor_encode.c \
      $qcbor/src/qcbor_decode.c $qcbor/src/UsefulBuf.c $qcbor/src/ieee754.c -lm
    common=($vendor/src/path.c $vendor/src/services.c $vendor/src/handle_db.c \
            $vendor/src/fs.c $vendor/src/gpfs.c)
    $CC "''${flags[@]}" -I$vendor/include -pthread -o build/clients/qsee-supplicant \
      $vendor/src/main.c $vendor/src/transport_qseecom.c "''${common[@]}" $vendor/src/notify.c
    $CC "''${flags[@]}" -I$vendor/include -o build/clients/qsee-app-loader \
      $vendor/src/app_loader.c $vendor/src/app_acquire.c $vendor/src/notify.c
    $CC "''${flags[@]}" -I$vendor/include -pthread \
      -o build/clients/ufs-rpmb-provider/liuqin-rpmb-supplicant \
      $vendor/src/liuqin_rpmb_main.c $vendor/src/rpmb.c $vendor/src/rpmb_ufs.c \
      $vendor/src/transport_qseecom.c "''${common[@]}"

    # pam-input authenticates the Linux account through PAM (/etc/pam.d/
    # liuqin-fpc-enrol) and derives the FPC credential input with OpenSSL
    # PBKDF2.  It is deliberately dynamic: it must load the host libpam and
    # libcrypto, never a static private copy.
    $CC -O2 -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror \
      -o build/pam-input $client/pam-input.c -lpam -lcrypto
    runHook postBuild
  '';

  # Runtime layout contract, checked at the end of installPhase: the entry points resolve
  # these exact names next to themselves.
  runtimeScripts = [
    "acceptance_input"
    "authorize_oem"
    "enrol_publish"
    "native_credential_preflight"
    "native_credentials"
    "oem_runtime"
    "user_credentials"
  ];

  installPhase = ''
    runHook preInstall
    client=$src/oem
    bundle=$out/libexec/liuqin-fpc-oem

    install -d $bundle/ufs-rpmb-provider

    install -m755 \
      build/clients/fpc_build_info \
      build/clients/qsee-gatekeeper \
      build/clients/qsee-supplicant \
      build/clients/qsee-app-loader \
      build/pam-input \
      $bundle/
    install -m755 build/clients/ufs-rpmb-provider/liuqin-rpmb-supplicant \
      $bundle/ufs-rpmb-provider/liuqin-rpmb-supplicant
    # Built by pkgs/fingerprint/libfprint-tod-fpc1264-oem.nix: it shares the
    # libfprint ABI of the TOD driver, so it is built and installed there and
    # only placed next to the runtime here (enrol_publish.py expects a sibling).
    install -m755 ${todDriver}/bin/fpc-oem-print $bundle/fpc-oem-print
    # enrol_publish.py refuses to run unless the whole trusted bundle is
    # present: it lstats $bundle, its own fpc-oem-print, user_credentials.py and
    # $bundle/tod/libfprint-tod-fpc1264-oem.so, requiring a root-owned regular
    # file (no symlink) with no group/other write bit.  The same copy is what
    # fpc-oem-print is pointed at (FP_TOD_DRIVERS_DIR=$bundle/tod) while it
    # serializes an accepted database, so this is a hard requirement of the
    # component's layout, not a convenience.
    install -Dm755 ${todDriver}/lib/libfprint-2/tod-1/libfprint-tod-fpc1264-oem.so \
      $bundle/tod/libfprint-tod-fpc1264-oem.so

    for script in ${lib.concatStringsSep " " finalAttrs.runtimeScripts}; do
      sed -e '1s|^#!.*|#!${python3}/bin/python3|' \
        $client/$script.py > $bundle/$script.py
      chmod 0555 $bundle/$script.py
      head -n1 $bundle/$script.py | grep -qF '#!${python3}/bin/python3' || {
        echo "liuqin-fpc-oem: shebang rewrite failed for $script.py" >&2
        exit 1
      }
    done

    # First NixOS adaptation: oem_runtime.py verifies and points
    # firmware_class.path at the OEM firmware directory next to itself (see the
    # patch file for why the operator-supplied directory wins).
    patch -p1 -d $bundle < ${./oem-runtime-firmware-dir.patch}
    grep -qF 'Path(os.environ.get("LIUQIN_FPC_OEM_FIRMWARE")' $bundle/oem_runtime.py || {
      echo "liuqin-fpc-oem: oem_runtime.py firmware-directory patch did not apply" >&2
      exit 1
    }

    # Second NixOS adaptation: the runtime checks the sensor power state via
    # the control driver's sysfs node (see the patch file for the mapping).
    patch -p1 -d $bundle < ${./oem-runtime-power-state.patch}
    grep -qF '_liuqin_power_state' $bundle/oem_runtime.py || {
      echo "liuqin-fpc-oem: oem_runtime.py power-state anchor is missing" >&2
      exit 1
    }

    # Third NixOS adaptation: acceptance_input.py addresses the root kernel
    # keyring through libkeyutils by soname, which neither the interpreter's
    # library search path nor the target package set can provide (that argument
    # resolves to the build platform's library).  The patch replaces the
    # library with the keyctl syscalls it wraps; the custody contract (key
    # description, permissions, 18 h timeout, one-use revocation, metadata) is
    # unchanged, so it remains interchangeable with the PAM module.
    patch -p1 -d $bundle < ${./acceptance-input-keyctl-syscalls.patch}
    grep -qF '_KeyctlSyscalls' $bundle/acceptance_input.py || {
      echo "liuqin-fpc-oem: acceptance_input.py keyctl patch did not apply" >&2
      exit 1
    }

    # pam-input resolves its PAM service with pam_start_confdir() from this
    # private directory, not from /etc: the component's layout keeps the
    # service file next to the helper.  Without it every credential operation
    # fails with phase=account_or_binary_fds_or_private_service.
    install -Dm644 $client/pam.d/liuqin-fpc-enrol $bundle/pam.d/liuqin-fpc-enrol
    install -Dm644 $client/pam.d/liuqin-fpc-enrol $out/etc/pam.d/liuqin-fpc-enrol

    for required in fpc_build_info qsee-gatekeeper qsee-supplicant qsee-app-loader \
                    pam-input fpc-oem-print tod/libfprint-tod-fpc1264-oem.so \
                    pam.d/liuqin-fpc-enrol \
                    ufs-rpmb-provider/liuqin-rpmb-supplicant \
                    ${lib.concatStringsSep " " (map (s: s + ".py") finalAttrs.runtimeScripts)}; do
      [ -f "$bundle/$required" ] || {
        echo "liuqin-fpc-oem: runtime bundle is missing $required" >&2
        exit 1
      }
    done
    runHook postInstall
  '';

  meta = {
    description = "OEM FPC1264 userspace runtime (QSEE clients, RPMB provider, PAM input) for the Xiaomi Pad 6 Pro";
    homepage = "https://github.com/yuzelingsha/xiaomipad-6pro-mainline";
    # MIT for the build integration and Python entry points, BSD-2-Clause for
    # the OEM C/PAM helpers, BSD-3-Clause for QCBOR, BSD-3-Clause-Clear for the
    # QSEE supplicant.
    license = with lib.licenses; [ mit bsd2 bsd3 bsd3Clear ];
    platforms = lib.platforms.linux;
  };
})
