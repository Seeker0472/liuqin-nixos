# SPDX-License-Identifier: MIT
{
  description = "NixOS for Xiaomi Pad 6 Pro (liuqin, SM8475) on latest stable Linux";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      # The two requireFile payloads that have no public source (the VPU image
      # and the SSC sensor config; see pkgs/firmware.nix) count as unfree.  The
      # same predicate serves the flake's own package sets and mkLiuqinSystem.
      allowLiuqinUnfree = pkg:
        builtins.elem (lib.getName pkg) [
          "liuqin-ssc-config.tar.zst"
          "liuqin-firmware-vpu.tar.zst"
        ];

      pkgsHost = import nixpkgs { system = "x86_64-linux"; };

      # x86_64 -> aarch64 cross package set carrying the liuqin overlay.
      pkgsArm = import nixpkgs {
        localSystem.system = "x86_64-linux";
        crossSystem.system = "aarch64-linux";
        overlays = [ self.overlays.default ];
        config.allowImportFromDerivation = true;
        config.allowUnfreePredicate = allowLiuqinUnfree;
      };
    in
    {
      overlays.default = import ./overlay.nix;

      lib = {
        inherit allowLiuqinUnfree;

        # Build a liuqin NixOS configuration from consumer modules. Injects
        # the liuqin module, the package overlay and the unfree predicate;
        # the consumer's own modules carry everything else (hostname, users,
        # desktop, storage layout).
        #
        #   nixosConfigurations.mypad = liuqin.lib.mkLiuqinSystem {
        #     modules = [ ./my-machine.nix ];
        #     crossBuild = true;
        #   };
        # `crossBuild` is opt-in for consumers because this flake's pkgsArm
        # package set is deliberately x86_64-hosted. The repository's own
        # configurations enable it below, so their full system/initrd can be
        # built on the standard x86_64 development host without binfmt.
        mkLiuqinSystem = { modules, system ? "aarch64-linux", crossBuild ? false }:
          lib.nixosSystem {
            inherit system;
            modules = [
              (if crossBuild then {
                # Keep the normal system on the same cross package set as the
                # RAM installer. This avoids trying to execute aarch64
                # builders on an x86_64 host with no binfmt registration.
                nixpkgs.pkgs = pkgsArm;
              } else {
                nixpkgs.overlays = [ self.overlays.default ];
                nixpkgs.config.allowUnfreePredicate = allowLiuqinUnfree;
              })
              self.nixosModules.liuqin
            ]
            ++ modules;
          };

        # Build the RAM-only NixOS installer independently from an installed
        # liuqin system. The installer uses nixpkgs' netboot live-root
        # machinery, while the caller supplies the device kernel/firmware
        # configuration in config/installer.nix or an equivalent module.
        mkLiuqinInstallerSystem = { modules ? [ ] }:
          lib.nixosSystem {
            system = "aarch64-linux";
            modules = [
              {
                # Use the existing x86_64 -> aarch64 package set so the
                # installer closure can be cross-built without executing
                # target binaries on the build host. The overlay and unfree
                # policy are already part of pkgsArm.
                nixpkgs.pkgs = pkgsArm;
              }
            ]
            ++ modules;
          };

        # A boot.img plus the netboot squashfs-backed live root. The init path
        # must be in the kernel command line because this image does not mount
        # a persistent root partition.
        mkLiuqinInstallerImages = configuration:
          let
            cfg = configuration.config;
            toplevel = cfg.system.build.liuqinLiveToplevel;
            bootargs = cfg.boot.kernelParams ++ [ "init=${toplevel}/init" ];
            mkImage = imageBootargs: pkgsArm.callPackage ./pkgs/bootimg.nix {
              kernel = cfg.boot.kernelPackages.kernel;
              gawk = pkgsHost.gawk;
              bootargs = lib.concatStringsSep " " imageBootargs;
              ramdisk = cfg.system.build.netbootRamdisk + "/initrd";
              extraOverlayDts = ./dts/liuqin-installer-overlay.dts;
            };
          in
          {
            bootimg = mkImage bootargs;
            inherit (cfg.system.build) netbootRamdisk squashfsStore toplevel;
          };

        # Build boot artifacts for an installed configuration. Installation
        # itself is intentionally not represented here: the only supported
        # entry point is the RAM installer image above, followed by
        # nixos-install from its live shell.
        mkLiuqinBootImages = configuration:
          let
            cfg = configuration.config;
            toplevel = cfg.system.build.toplevel;
          in
          {
            bootimg = pkgsArm.callPackage ./pkgs/bootimg.nix {
              kernel = cfg.boot.kernelPackages.kernel;
              gawk = pkgsHost.gawk;
              bootargs = lib.concatStringsSep " " (
                cfg.boot.kernelParams ++ [ "init=${toplevel}/init" ]
              );
              ramdisk = cfg.system.build.initialRamdisk + "/initrd";
            };
          }
          // lib.optionalAttrs (cfg.hardware.liuqin.boot.loader == "uboot") {
            bootdir = cfg.system.build.liuqinBootDir;
          };
      };

      packages.x86_64-linux =
        let
          normalConfiguration = self.nixosConfigurations.liuqin;
          normalKernel = normalConfiguration.config.hardware.liuqin.package;
          installerConfiguration = self.nixosConfigurations.liuqin-installer;
          installerKernel = installerConfiguration.config.boot.kernelPackages.kernel;
          exampleImages = self.lib.mkLiuqinBootImages normalConfiguration;
          demoImages = self.lib.mkLiuqinBootImages self.nixosConfigurations.demo;
          installerImages = self.lib.mkLiuqinInstallerImages
            installerConfiguration;
          mkbootimgTool = pkgsHost.callPackage ./pkgs/mkbootimg.nix { };
        in
        {
          # Keep these outputs tied to the kernels selected by the actual
          # configurations. That makes package inspection unambiguous: the
          # normal kernel is the installed-system kernel and the installer
          # kernel is the built-in-USB variant.
          kernel = normalKernel;
          installer-kernel = installerKernel;
          dtb = pkgsArm.liuqinKernelDtb;
          installer-dtb = pkgsArm.liuqinInstallerKernelDtb;
          # Low-level bring-up artifact only: this has an empty ramdisk and
          # no `init=` command line. Use installer-bootimg or bootimg-nixos
          # for a bootable NixOS environment.
          bootimg-kernel-only = pkgsArm.callPackage ./pkgs/bootimg.nix {
            kernel = normalKernel;
            gawk = pkgsHost.gawk;
          };
          power-keyd = pkgsArm.liuqinPowerKeyd;
          # Boot image for the EXAMPLE configuration (config/example.nix).
          # Your own configuration: use lib.mkLiuqinBootImages instead.
          bootimg-nixos = exampleImages.bootimg;
          demo-bootdir = demoImages.bootdir;
          demo-bootimg = demoImages.bootimg;
          # Full NixOS live installer: kernel plus a netboot squashfs/root
          # overlay packed into the ABL boot.img ramdisk. This is the only
          # supported initial-install path and is RAM-boot-only.
          installer-bootimg = installerImages.bootimg;
          installer-ramdisk = installerImages.netbootRamdisk;
          installer-squashfs = installerImages.squashfsStore;
          # Host wrapper for the checked-in U-Boot pipeline. The dualboot tree
          # is a sibling repository and therefore cannot be imported into a
          # pure flake evaluation; this command keeps the build declarative
          # while preserving that repository's package-boota.sh assertions.
          uboot-build = pkgsHost.writeShellApplication {
            name = "liuqin-uboot-build";
            runtimeInputs = [
              pkgsHost.bash pkgsHost.bc pkgsHost.bison pkgsHost.coreutils
              pkgsHost.dtc pkgsHost.findutils pkgsHost.flex pkgsHost.gawk
              pkgsHost.gcc pkgsHost.gnugrep pkgsHost.gnumake pkgsHost.gzip
              pkgsHost.perl pkgsHost.python3 pkgsHost.xz pkgsHost.zstd
              mkbootimgTool
              pkgsArm.stdenv.cc
            ];
            text = ''
              workspace="''${LIUQIN_WORKSPACE_ROOT:-$PWD/..}"
              test -x "$workspace/liuqin-dualboot/u-boot/build.sh" || {
                echo "liuqin-uboot-build: set LIUQIN_WORKSPACE_ROOT to the workspace containing liuqin-dualboot" >&2
                exit 2
              }
              exec bash "$workspace/liuqin-dualboot/u-boot/build.sh" "$@"
            '';
          };
        };

      nixosModules.liuqin = import ./modules/liuqin;

      # Example configuration (config/example.nix). Real
      # deployments define their own via lib.mkLiuqinSystem; this one backs
      # the flake's packages and eval check.
      nixosConfigurations.liuqin = self.lib.mkLiuqinSystem {
        crossBuild = true;
        modules = [ ./config/example.nix ];
      };

      # Complete demo system (GNOME, touch, network, audio, Bluetooth, sensors)
      # on the dual-boot layout; see config/demo.nix.
      nixosConfigurations.demo = self.lib.mkLiuqinSystem {
        crossBuild = true;
        modules = [ ./config/demo.nix ];
      };

      # RAM-only NixOS installation environment. It deliberately does not
      # import modules/liuqin, because an installer must not mount or mutate a
      # target root merely by booting.
      nixosConfigurations.liuqin-installer = self.lib.mkLiuqinInstallerSystem {
        modules = [ ./config/installer.nix ];
      };

      # Everything that must at least evaluate.
      checks.x86_64-linux.eval-nixos =
        self.nixosConfigurations.liuqin.config.system.build.toplevel;
      checks.x86_64-linux.eval-installer =
        self.nixosConfigurations.liuqin-installer.config.system.build.toplevel;
    };
}
