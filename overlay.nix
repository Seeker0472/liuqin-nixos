# SPDX-License-Identifier: MIT
#
# liuqin package overlay. Everything device-specific lives here; the NixOS
# module references pkgs.liuqin*.
final: prev:

let
  lib = prev.lib;
in
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

  # /boot payload for the U-Boot loader path (kernel + initrd + DTB carrying
  # the command line). Built by the NixOS module via system.build; the
  # arguments come from the configuration, so it is not instantiated here.
  liuqinBootdir = args: final.callPackage ./pkgs/bootdir.nix args;

  # --- Device packages ---
  liuqinPowerKeyd = final.callPackage ./pkgs/power-keyd.nix { };
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

  # alsa-ucm-conf with the liuqin card files added.
  alsa-ucm-conf = prev.alsa-ucm-conf.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      install -Dm0644 ${./data/ucm2/Qualcomm/sm8450/Xiaomi-Pad-6-Pro/HiFi.conf} \
        $out/share/alsa/ucm2/Qualcomm/sm8450/Xiaomi-Pad-6-Pro/HiFi.conf
      install -Dm0644 ${./data/ucm2/conf.d/sm8450/Xiaomi-Pad-6-Pro.conf} \
        $out/share/alsa/ucm2/conf.d/sm8450/Xiaomi-Pad-6-Pro.conf
    '';
  });

  # Firmware tree assembled from requireFile placeholders (operator-supplied
  # stock-ROM payloads); see pkgs/firmware.nix.
  liuqinFirmware = final.callPackage ./pkgs/firmware.nix { };
  liuqinInitrdFirmware = final.callPackage ./pkgs/firmware-initrd.nix {
    firmware = final.liuqinFirmware;
  };
}
