# SPDX-License-Identifier: MIT
#
# liuqin package overlay. Everything device-specific lives here; the NixOS
# module references pkgs.liuqin*.
final: prev:

{
  # --- Kernel (linuxManualConfig, aarch64 defconfig + liuqin answers) ---
  # One kernel with every board feature: USB3 peripheral data path, Type-C
  # host/OTG, DP Alt Mode and the MiPPS ABI.  The per-feature bring-up
  # profiles are gone - they existed to bisect the bring-up, and every one of
  # them has been validated on hardware.
  liuqinKernel = final.callPackage ./pkgs/kernel { };
  # RAM installer kernel: same display/earlycon fixes, with the input and USB
  # host paths promoted to built-in because the installer has no module tree.
  liuqinInstallerKernel = final.callPackage ./pkgs/kernel { installer = true; };

  liuqinKernelDtb = prev.runCommand "liuqin-dtb-${final.liuqinKernel.version}"
    { nativeBuildInputs = [ final.buildPackages.dtc ]; } ''
    mkdir -p $out
    cp ${final.liuqinKernel}/dtbs/qcom/sm8475-xiaomi-liuqin.dtb $out/

    # The scheduler only learns that the three Kryo clusters differ through
    # these two properties (pkgs/kernel/patches/0011-liuqin-cpu-topology-thermal.patch); with them missing every CPU
    # falls back to cpu_capacity 1024 and SD_ASYM_CPUCAPACITY is never set, and
    # the failure is silent.  Assert the values, not just presence: setting
    # 1024 on every CPU would pass a count-only check.
    dtc -I dtb -O dts -o board.dts $out/sm8475-xiaomi-liuqin.dtb
    check() {
      n=$(grep -cF "$1" board.dts || true)
      [ "$n" -eq "$2" ] || {
        echo "error: board DTB has $n lines of '$1', expected $2" >&2
        echo "       (the CPU capacity/energy-model patch 0011-liuqin-cpu-topology-thermal.patch is missing)" >&2
        exit 1
      }
    }
    check "capacity-dmips-mhz = <0x400>" 4
    check "capacity-dmips-mhz = <0x8cd>" 3
    check "capacity-dmips-mhz = <0x952>" 1
    check "dynamic-power-coefficient = <0x64>" 4
    check "dynamic-power-coefficient = <0x101>" 3
    check "dynamic-power-coefficient = <0x1fd>" 1
  '';
  liuqinInstallerKernelDtb = prev.runCommand "liuqin-installer-dtb-${final.liuqinInstallerKernel.version}" { } ''
    mkdir -p $out
    cp ${final.liuqinInstallerKernel}/dtbs/qcom/sm8475-xiaomi-liuqin.dtb $out/
  '';

  # --- boot.img tooling ---
  mkbootimg = final.callPackage ./pkgs/mkbootimg.nix { };
  liuqinBootimg = final.callPackage ./pkgs/bootimg {
    kernel = final.liuqinKernel;
    # bootimg.nix runs its DT/symbol synthesis on the build host.  In the
    # aarch64 package set the unqualified gawk would be an aarch64 executable
    # and cannot run during an x86_64 cross build.
    gawk = final.buildPackages.gawk;
  };

  # --- U-Boot ---
  # The bootloader this device boots, built here rather than in a sibling
  # checkout: Qualcomm's U-Boot fork plus the liuqin port (pkgs/u-boot/patches
  # for the files it shares with its base, pkgs/u-boot/files for the ones it
  # adds; pkgs/u-boot/verify-port.sh proves the three reproduce the dev tree
  # byte for byte). The boot.img is packaged by pkgs/bootimg/default.nix, the
  # same ABL pipeline as the
  # kernel image. buildPackages is the x86_64 set that runs the host tools.
  liuqinUboot = final.callPackage ./pkgs/u-boot { hostPkgs = final.buildPackages; };

  # --- Device packages ---
  liuqinPowerKeyd = final.callPackage ./pkgs/power-keyd { };

  # --- Device glue --------------------------------------------------------
  # The commands the modules wire into units (modules/liuqin/*.nix):
  # the script bodies live here, the unit ordering stays in the module. Each
  # command is parameterised (state paths, sysfs roots, actions) so the whole
  # flow can be exercised against fixture trees, with no tablet involved.
  liuqinScreenRefresh = final.callPackage ./pkgs/screen-refresh.nix { };
  liuqinBacklightDefault = final.callPackage ./pkgs/backlight.nix { };
  liuqinPersistProvision = final.callPackage ./pkgs/persist-provision.nix { };
  # persistent-root identity guard, run by modules/liuqin/initrd-guard.nix
  liuqinStorageGuard = final.callPackage ./pkgs/storage-guard.nix { };
  liuqinFirmwarePath = final.callPackage ./pkgs/firmware-path.nix { };
  liuqinWlanMac = final.callPackage ./pkgs/wlan-mac.nix { };
  liuqinBtPublicAddr = final.callPackage ./pkgs/bt-public-addr.nix { };
  liuqinBtNv = final.callPackage ./pkgs/bt-nv { };
  liuqinSlpi = final.callPackage ./pkgs/slpi.nix { };
  liuqinSensorProxyRefresh = final.callPackage ./pkgs/sensor-proxy-refresh.nix { };

  # --- USB2 control channel ---
  # The configfs gadget (mkLiuqinUsbGadget takes the USB strings and the two
  # consumer differences) and the telnetd login wrapper, shared by the RAM
  # installer and hardware.liuqin.usbShell. See pkgs/usb-gadget.nix.
  mkLiuqinUsbGadget = final.callPackage ./pkgs/usb-gadget.nix { };
  liuqinUsbLogin = final.callPackage ./pkgs/usb-login.nix { };

  # --- Camera ---
  # The patched libcamera of the AF series (pkgs/libcamera-af/), built as a
  # standalone package instead of an override of pkgs.libcamera: replacing
  # libcamera in the closure rebuilds ~142 derivations (webkitgtk included),
  # which is not worth it while the series is upstream-bound.  Consumers that
  # need autofocus take this library by path - the demo module points
  # pipewire/wireplumber at it with LD_LIBRARY_PATH (same soname, same
  # version, patches confined to the simple pipeline's implementation).
  liuqinLibcameraAf = final.callPackage ./pkgs/libcamera-af { };
  # Convenience: the AF library's own `cam` under a distinct name (its
  # RUNPATH already selects the patched library).
  liuqinCamAf = prev.runCommand "cam-af" { } ''
    mkdir -p $out/bin
    cat > $out/bin/cam-af <<'SH'
    #!${prev.runtimeShell}
    exec ${final.liuqinLibcameraAf}/bin/cam "$@"
    SH
    chmod +x $out/bin/cam-af
  '';

  # AP-side Xiaomi MiPPS authentication coordinator.  It is intentionally
  # separate from qcom-battmgr: the ADSP owns PD and the daemon only consumes
  # the narrow qcom-battery ABI.  Runtime key files are never part of Nix.
  liuqinMippsd = final.callPackage ./pkgs/mipps-daemon.nix { };

  liuqinHexagonrpc = final.callPackage ./pkgs/hexagonrpc { };
  liuqinSensorsConfig = final.callPackage ./pkgs/sensors-config.nix { };

  # libssc (and its `ssccli`) come from nixpkgs: 0.4.4, the same upstream
  # release this repository used to pin itself, but tracked by nixpkgs and
  # served from cache.nixos.org. The former liuqinLibssc/liuqinQrtr pair only
  # carried test-harness overrides for the upstream suite and was wired into
  # nothing that ships - both are gone.
  #
  # Bounded, sequential real-sample checks for the SSC accelerometer,
  # gyroscope, and light sensors.  These are deliberately separate from
  # iio-sensor-proxy so each sensor can be accepted independently.
  liuqinSensorCheck = final.callPackage ./pkgs/sensors-tools.nix { };

  # iio-sensor-proxy with the liuqin SSC patches 0003-0006; the hexagonrpcd
  # side is a single patch (0001-hexagonrpcd-implement-ssc-file-service),
  # applied in pkgs/hexagonrpc/default.nix.
  liuqinIioSensorProxy = final.callPackage ./pkgs/iio-sensor-proxy { };

  # The device's UCM2 files as a leaf package.  Deliberately NOT an override of
  # alsa-ucm-conf: that package is a build input of alsa-lib, so patching it
  # would rebuild every audio consumer in the closure.  See pkgs/alsa-ucm/default.nix.
  liuqinAlsaUcm = final.callPackage ./pkgs/alsa-ucm { };

  # Flashlight Quick Settings extension (data-only: shell JS + icons).  In the
  # overlay so machine configurations reference it as pkgs.liuqinGnomeFlashlight
  # and a copied-out configuration keeps working.
  liuqinGnomeFlashlight = final.callPackage ./pkgs/gnome-flashlight { };

  # Firmware tree assembled from requireFile placeholders (operator-supplied
  # stock-ROM payloads); see pkgs/firmware.nix.
  liuqinFirmware = final.callPackage ./pkgs/firmware.nix { };
  liuqinInitrdFirmware = final.callPackage ./pkgs/firmware-initrd.nix {
    firmware = final.liuqinFirmware;
  };

  # --- OEM FPC1264 fingerprint stack (hardware.liuqin.fingerprint) ----------
  # Cross-only adaptation of the upstream libfprint-tod the two compiled
  # packages build against.  libfprint's meson configure RUNS
  # tests/unittest_inspector.py; patchShebangs can only rewrite that helper's
  # shebang when a python3 is visible on PATH, and a cross build only puts
  # nativeBuildInputs there - none of libfprint's are a python3 - so the helper
  # keeps a /usr/bin/env shebang that does not exist on NixOS and meson aborts
  # with "Could not execute command".  Adding the build-host interpreter to the
  # native build inputs is the upstream-equivalent fix (nixpkgs is simply not
  # cross-clean here).  Only build-time helper shebangs change; the installed
  # library is unchanged, and native builds keep using the cached derivation.
  liuqinFpcOemLibfprintTod =
    if final.stdenv.buildPlatform == final.stdenv.hostPlatform
    then prev.libfprint-tod
    else
      let
        # libfprint generates its udev hwdb by BUILDING AND RUNNING the target
        # helper fprint-list-udev-hwdb; meson refuses that without an
        # exe_wrapper.  The sandbox has no binfmt, so hand meson qemu-user (a
        # build-time dependency only; it stays out of the device closure).
        exeWrapper =
          "${final.buildPackages.qemu-user}/bin/qemu-${final.stdenv.hostPlatform.qemuArch}";
        crossFile = final.buildPackages.writeText "liuqin-fpc-oem-meson-cross-file.conf" ''
          [binaries]
          exe_wrapper = '${exeWrapper}'
        '';
      in
      prev.libfprint-tod.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.buildPackages.python3 ];
        # Appended, not replacing: nixpkgs' own cross file (if any) is merged
        # with this one by meson, later keys winning.
        mesonFlags = (old.mesonFlags or [ ]) ++ [ "--cross-file=${crossFile}" ];
      });

  # One vendored source tree of the OEM component feeds the three packages, so
  # the revision cannot drift between the runtime, the TOD driver and the
  # fprintd patch; the two libraries the component builds against are pinned
  # from their own upstreams instead.  Vendored (not fetched) from
  # yzddmr6/xiaomipad-6pro-mainline PR #11, head 17c534b of the yuzelingsha
  # fork - see NOTICE.
  liuqinFpcOemSrc = ./pkgs/fingerprint/fpc-oem-src;
  liuqinFpcOemQcbor = final.callPackage ./pkgs/fingerprint/qcbor.nix { };
  liuqinFpcOemSupplicant = final.callPackage ./pkgs/fingerprint/qsee-supplicant.nix { };
  # libfprint TOD module (fpc1264_oem) plus the FpPrint serializer; the nixpkgs
  # fprintd module turns passthru.driverPath into FP_TOD_DRIVERS_DIR.
  liuqinFpcOemTodDriver = final.callPackage ./pkgs/fingerprint/libfprint-tod-fpc1264-oem.nix {
    src = final.liuqinFpcOemSrc;
    libfprint-tod = final.liuqinFpcOemLibfprintTod;
  };
  # Userspace runtime bundle (QSEE clients, TEE/RPMB supplicant, PAM input and
  # the Python entry points) under one prefix; it owns fpc-oem-print from the
  # TOD package so every helper the entry points expect is colocated.
  liuqinFpcOem = final.callPackage ./pkgs/fingerprint/liuqin-fpc-oem.nix {
    src = final.liuqinFpcOemSrc;
    qcbor = final.liuqinFpcOemQcbor;
    supplicant = final.liuqinFpcOemSupplicant;
    todDriver = final.liuqinFpcOemTodDriver;
  };
  # PAM module that derives the FPC1264 credential input when the account
  # authenticates with its password, so the TOD driver's enrolment runs from
  # the desktop without a second prompt (see modules/liuqin/fingerprint.nix).
  liuqinPamFpc = final.callPackage ./pkgs/fingerprint/pam-liuqin-fpc.nix { };
  # fprintd 1.94.5 with the OEM adaptive-template persistence change, linked
  # against the same libfprint-tod the TOD driver uses (this is also the
  # override nixpkgs applies for fprintd-tod).
  liuqinFprintdOem = final.callPackage ./pkgs/fingerprint/fprintd-oem.nix {
    src = final.liuqinFpcOemSrc;
    libfprint-tod = final.liuqinFpcOemLibfprintTod;
    # Build-host glib for gdbus-codegen during cross builds; identical to glib
    # in a native build.
    glibBuild = final.buildPackages.glib;
  };
}
