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
  liuqinKernel = final.callPackage ./kernel { };
  # RAM installer kernel: same display/earlycon fixes, with the input and USB
  # host paths promoted to built-in because the installer has no module tree.
  liuqinInstallerKernel = final.callPackage ./kernel { installer = true; };

  liuqinKernelDtb = prev.runCommand "liuqin-dtb-${final.liuqinKernel.version}"
    { nativeBuildInputs = [ final.buildPackages.dtc ]; } ''
    mkdir -p $out
    cp ${final.liuqinKernel}/dtbs/qcom/sm8475-xiaomi-liuqin.dtb $out/

    # The scheduler only learns that the three Kryo clusters differ through
    # these two properties (patches/kernel/0016); with them missing every CPU
    # falls back to cpu_capacity 1024 and SD_ASYM_CPUCAPACITY is never set, and
    # the failure is silent.  Assert the values, not just presence: setting
    # 1024 on every CPU would pass a count-only check.
    dtc -I dtb -O dts -o board.dts $out/sm8475-xiaomi-liuqin.dtb
    check() {
      n=$(grep -cF "$1" board.dts || true)
      [ "$n" -eq "$2" ] || {
        echo "error: board DTB has $n lines of '$1', expected $2" >&2
        echo "       (the CPU capacity/energy-model patch 0016 is missing)" >&2
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
  liuqinBootimg = final.callPackage ./pkgs/bootimg.nix {
    kernel = final.liuqinKernel;
    # bootimg.nix runs its DT/symbol synthesis on the build host.  In the
    # aarch64 package set the unqualified gawk would be an aarch64 executable
    # and cannot run during an x86_64 cross build.
    gawk = final.buildPackages.gawk;
  };

  # --- U-Boot ---
  # The bootloader this device boots, built here rather than in a sibling
  # checkout: Qualcomm's U-Boot fork plus the liuqin port (u-boot/patches for
  # the files it shares with its base, u-boot/files for the ones it adds;
  # u-boot/verify-port.sh proves the three reproduce the dev tree byte for byte). The
  # boot.img is packaged by pkgs/bootimg.nix, the same ABL pipeline as the
  # kernel image. buildPackages is the x86_64 set that runs the host tools.
  liuqinUboot = final.callPackage ./u-boot { hostPkgs = final.buildPackages; };

  # --- Device packages ---
  liuqinPowerKeyd = final.callPackage ./pkgs/power-keyd.nix { };

  # --- Device glue --------------------------------------------------------
  # The commands the module wires into units (modules/liuqin/hardware.nix):
  # the script bodies live here, the unit ordering stays in the module. Each
  # command is parameterised (state paths, sysfs roots, actions) so the whole
  # flow can be exercised against fixture trees, with no tablet involved.
  liuqinScreenRefresh = final.callPackage ./pkgs/screen-refresh.nix { };
  liuqinBacklightDefault = final.callPackage ./pkgs/backlight.nix { };
  liuqinPersistProvision = final.callPackage ./pkgs/persist-provision.nix { };
  liuqinFirmwarePath = final.callPackage ./pkgs/firmware-path.nix { };
  liuqinWlanMac = final.callPackage ./pkgs/wlan-mac.nix { };
  liuqinBtPublicAddr = final.callPackage ./pkgs/bt-public-addr.nix { };
  liuqinBtNv = final.callPackage ./pkgs/bt-nv.nix { };
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

  liuqinHexagonrpc = final.callPackage ./pkgs/hexagonrpc.nix { };
  liuqinSensorsConfig = final.callPackage ./pkgs/sensors-config.nix { };

  # libssc at the pinned downstream commit.
  liuqinQrtr = final.callPackage ./pkgs/qrtr.nix { };
  liuqinLibssc = final.callPackage ./pkgs/libssc.nix {
    qrtr = final.liuqinQrtr;
  };
  # Bounded, sequential real-sample checks for the SSC accelerometer,
  # gyroscope, and light sensors.  These are deliberately separate from
  # iio-sensor-proxy so each sensor can be accepted independently.
  liuqinSensorCheck = final.callPackage ./pkgs/sensors-tools.nix { };

  # iio-sensor-proxy with the liuqin SSC patches 0003-0006; the hexagonrpcd
  # side is a single patch (0001-hexagonrpcd-implement-ssc-file-service),
  # applied in pkgs/hexagonrpc.nix.
  liuqinIioSensorProxy = prev.iio-sensor-proxy.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./data/sensors-patches/0003-iio-sensor-proxy-start-preclaimed-coldplug-sensor.patch
      ./data/sensors-patches/0004-iio-sensor-proxy-serialize-ssc-accel-polling.patch
      ./data/sensors-patches/0005-iio-sensor-proxy-cancel-released-pending-claims.patch
      ./data/sensors-patches/0006-iio-sensor-proxy-broadcast-sensor-availability.patch
    ];
  });

  # The device's UCM2 files as a leaf package.  Deliberately NOT an override of
  # alsa-ucm-conf: that package is a build input of alsa-lib, so patching it
  # would rebuild every audio consumer in the closure.  See pkgs/alsa-ucm.nix.
  liuqinAlsaUcm = final.callPackage ./pkgs/alsa-ucm.nix { };

  # Firmware tree assembled from requireFile placeholders (operator-supplied
  # stock-ROM payloads); see pkgs/firmware.nix.
  liuqinFirmware = final.callPackage ./pkgs/firmware.nix { };
  liuqinInitrdFirmware = final.callPackage ./pkgs/firmware-initrd.nix {
    firmware = final.liuqinFirmware;
  };
}
