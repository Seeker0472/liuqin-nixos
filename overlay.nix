# SPDX-License-Identifier: MIT
#
# liuqin package overlay. Everything device-specific lives here; the NixOS
# module references pkgs.liuqin*.
final: prev:

{
  # --- Kernel (linuxManualConfig, aarch64 defconfig + liuqin answers) ---
  liuqinKernel = final.callPackage ./kernel { };
  # RAM installer kernel: same display/earlycon fixes, with the input and USB
  # host paths promoted to built-in because the installer has no module tree.
  liuqinInstallerKernel = final.callPackage ./kernel { installer = true; };

  liuqinKernelDtb = prev.runCommand "liuqin-dtb-${final.liuqinKernel.version}" { } ''
    mkdir -p $out
    cp ${final.liuqinKernel}/dtbs/qcom/sm8475-xiaomi-liuqin.dtb $out/
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

  # --- USB2 control channel ---
  # The configfs gadget (mkLiuqinUsbGadget takes the USB strings and the two
  # consumer differences) and the telnetd login wrapper, shared by the RAM
  # installer and hardware.liuqin.usbShell. See pkgs/usb-gadget.nix.
  mkLiuqinUsbGadget = final.callPackage ./pkgs/usb-gadget.nix { };
  liuqinUsbLogin = final.callPackage ./pkgs/usb-login.nix { };
  liuqinHexagonrpc = final.callPackage ./pkgs/hexagonrpc.nix { };
  liuqinSensorsConfig = final.callPackage ./pkgs/sensors-config.nix { };

  # libssc at the pinned downstream commit.
  liuqinLibssc = final.callPackage ./pkgs/libssc.nix { };

  # iio-sensor-proxy with the liuqin SSC patches (4 of 6; 0001/0002 target
  # hexagonrpcd and are applied there in pkgs/hexagonrpc.nix).
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

