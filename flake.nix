# SPDX-License-Identifier: MIT
{
  description = "NixOS for Xiaomi Pad 6 Pro (liuqin, SM8475) on latest stable Linux";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      # requireFile payloads (firmware, SSC config) count as unfree; the same
      # predicate mkLiuqinSystem injects, applied to the flake's own package
      # sets so `nix flake check` can evaluate them.
      allowLiuqinUnfree = pkg:
        builtins.elem (lib.getName pkg) [
          "liuqin-ssc-config.tar.zst"
          "liuqin-firmware-touch.tar.zst"
          "liuqin-firmware-dsp.tar.zst"
          "liuqin-firmware-gpu.tar.zst"
          "liuqin-firmware-bt.tar.zst"
          "liuqin-firmware-wlan-board.tar.zst"
          "liuqin-firmware-topology.tar.zst"
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
        #   };
        mkLiuqinSystem = { modules, system ? "aarch64-linux" }:
          lib.nixosSystem {
            inherit system;
            modules = [
              {
                nixpkgs.overlays = [ self.overlays.default ];
                nixpkgs.config.allowUnfreePredicate = allowLiuqinUnfree;
              }
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
            bootargs = cfg.boot.kernelParams
              ++ [ "init=${toplevel}/init" ];
          in
          {
            bootimg = pkgsArm.callPackage ./pkgs/bootimg.nix {
              kernel = cfg.boot.kernelPackages.kernel;
              bootargs = lib.concatStringsSep " " bootargs;
              ramdisk = cfg.system.build.netbootRamdisk + "/initrd";
            };
            inherit (cfg.system.build) netbootRamdisk squashfsStore toplevel;
          };

        # Deployable artifacts for ANY liuqin nixosConfiguration (this
        # flake's example or a consumer's own). Returns:
        #   bootimg          boot.img: configuration's kernel + NixOS initrd
        #                    + boot.kernelParams cmdline
        #   rootfsImage      pre-built ext4 rootfs of the whole closure,
        #                    for `fastboot flash userdata` (layout
        #                    whole-userdata) or `--target linux` (layout
        #                    linux-partition)
        #   bootdir          /boot payload for boot.loader = "uboot": Image,
        #                    initrd.img and a DTB carrying the command line
        #   rootMarkerCheck  host-arch tmpfiles marker byte-consistency check
        #
        # rootfsImage builds the aarch64 closure natively: an x86_64 host
        # needs qemu binfmt (boot.binfmt.emulatedSystems) or an aarch64
        # remote builder. bootimg cross-compiles and needs neither.
        mkLiuqinImages = configuration:
          let
            cfg = configuration.config;
            toplevel = cfg.system.build.toplevel;
          in
          {
            bootimg = pkgsArm.callPackage ./pkgs/bootimg.nix {
              kernel = cfg.boot.kernelPackages.kernel;
              bootargs = lib.concatStringsSep " " (
                cfg.boot.kernelParams ++ [ "init=${toplevel}/init" ]
              );
              ramdisk = cfg.system.build.initialRamdisk + "/initrd";
            };

            # Pre-built ext4 rootfs image for `fastboot flash userdata`. The
            # initrd storage guard reads /etc/liuqin-nixos-root BEFORE
            # sysroot is mounted, so the marker must exist in the image from
            # the start (stage-2 tmpfiles only repairs it afterwards).
            rootfsImage = pkgsHost.callPackage (nixpkgs + "/nixos/lib/make-ext4-fs.nix") {
              storePaths = [ toplevel ];
              volumeLabel = cfg.hardware.liuqin.storage.rootLabel;
              populateImageCommands =
                let
                  marker = cfg.hardware.liuqin.rootMarkerContent;
                  # U-Boot path: the kernel, initrd and the cmdline-carrying DTB
                  # live on the root filesystem's own /boot, so a single flash
                  # installs both the system and what the bootloader reads.
                  bootFiles =
                    lib.optionalString
                      (cfg.hardware.liuqin.boot.loader == "uboot") ''
                        mkdir -p ./files/boot
                        cp -rL ${cfg.system.build.liuqinBootDir}/. ./files/boot/
                        chmod -R u+w ./files/boot
                      '';
                in
                ''
                  mkdir -p ./files/etc ./files/var ./files/tmp ./files/root ./files/home
                  chmod 0755 ./files/var ./files/home ./files/etc
                  chmod 1777 ./files/tmp
                  chmod 0700 ./files/root
                  # Dereference: environment.etc entries are store symlinks
                  # and the guard requires real regular files on the rootfs.
                  cp -rL ${toplevel}/etc/. ./files/etc/
                  chmod -R u+w ./files/etc
                  printf '%s' '${marker}' > ./files/etc/liuqin-nixos-root
                  chmod 0644 ./files/etc/liuqin-nixos-root
                  ln -s ${toplevel}/init ./files/init
                  ${bootFiles}
                '';
            };

            bootdir = cfg.system.build.liuqinBootDir;

            # Host-arch copy of the tmpfiles marker byte-consistency check
            # from modules/liuqin/initrd-guard.nix: runs the exact
            # systemd.tmpfiles rule through systemd-tmpfiles --create --root
            # and requires the result to be byte-identical to the guard
            # marker. Also asserted into the aarch64 system closure via an
            # activation script.
            rootMarkerCheck = cfg.hardware.liuqin.rootMarkerCheck pkgsHost;
          };
      };

      packages.x86_64-linux =
        let
          exampleImages = self.lib.mkLiuqinImages self.nixosConfigurations.liuqin;
          demoImages = self.lib.mkLiuqinImages self.nixosConfigurations.demo;
          installerImages = self.lib.mkLiuqinInstallerImages
            self.nixosConfigurations.liuqin-installer;
          mkbootimgTool = pkgsHost.callPackage ./pkgs/mkbootimg.nix { };
          # Build the operator-only F2FS tools without SELinux userspace;
          # static libselinux does not link in this musl cross build.
          f2fsToolsStatic = pkgsArm.pkgsStatic.f2fs-tools.overrideAttrs (old: {
            buildInputs = builtins.filter
              (input: pkgsArm.lib.getName input != "libselinux")
              old.buildInputs;
            configureFlags = (old.configureFlags or [ ]) ++ [ "--without-selinux" ];
          });
          smokeInitramfs = pkgsHost.callPackage ./pkgs/smoke-initramfs.nix {
            busybox = pkgsArm.pkgsStatic.busybox;
            gptfdisk = pkgsArm.pkgsStatic.gptfdisk;
            f2fsTools = f2fsToolsStatic;
            smokeInit = ./initramfs/liuqin-smoke-init;
          };
        in
        {
          kernel = pkgsArm.liuqinKernel;
          dtb = pkgsArm.liuqinKernelDtb;
          bootimg = pkgsArm.liuqinBootimg;
          power-keyd = pkgsArm.liuqinPowerKeyd;
          # Image bundle of the EXAMPLE configuration (config/example.nix).
          # Your own configuration: use lib.mkLiuqinImages instead.
          inherit (exampleImages) rootfsImage;
          bootimg-nixos = exampleImages.bootimg;
          root-marker-check = exampleImages.rootMarkerCheck;
          # Image bundle of the DEMO configuration (config/demo.nix): flash
          # demo-rootfsImage to the `linux` partition and boot with U-Boot.
          demo-rootfsImage = demoImages.rootfsImage;
          # Sparse form lets AOSP fastboot resparse a large ext4 image into
          # max-download-size-sized transfers. The raw image remains the
          # canonical artifact and is used for local filesystem validation.
          rootfsImageSparse = pkgsHost.runCommand "liuqin-rootfs-sparse.img" {
            nativeBuildInputs = [ pkgsHost.android-tools ];
          } ''
            img2simg ${exampleImages.rootfsImage} $out
          '';
          demo-rootfsImageSparse = pkgsHost.runCommand "liuqin-demo-rootfs-sparse.img" {
            nativeBuildInputs = [ pkgsHost.android-tools ];
          } ''
            img2simg ${demoImages.rootfsImage} $out
          '';
          demo-bootdir = demoImages.bootdir;
          demo-bootimg = demoImages.bootimg;
          # Minimal RAM bring-up image: static aarch64 BusyBox initramfs plus
          # the Nix-built kernel/DTB. It is diagnostic only and never writes
          # partitions; install remains the measured host-side fastboot path.
          smoke-initramfs = smokeInitramfs;
          smoke-bootimg = pkgsHost.callPackage ./pkgs/bootimg.nix {
            kernel = pkgsArm.liuqinKernel;
            ramdisk = smokeInitramfs;
            mkbootimg = mkbootimgTool;
          };
          # Full NixOS live installer: kernel plus a netboot squashfs/root
          # overlay packed into the ABL boot.img ramdisk. This is RAM-boot-only.
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
          # Host-side installer; runs on x86_64 against fastboot.
          installer = pkgsHost.writers.writePython3Bin "liuqin-install" {
            libraries = [ ];
            flakeIgnore = [ "E501" "E265" ];
            makeWrapperArgs = [ "--prefix PATH : ${pkgsHost.android-tools}/bin" ];
          } (builtins.readFile ./tools/install.py);
        };

      nixosModules.liuqin = import ./modules/liuqin;

      # Example / smoke-test configuration (config/example.nix). Real
      # deployments define their own via lib.mkLiuqinSystem; this one backs
      # the flake's packages and eval check.
      nixosConfigurations.liuqin = self.lib.mkLiuqinSystem {
        modules = [ ./config/example.nix ];
      };

      # Complete demo system (GNOME, touch, network, audio, Bluetooth, sensors)
      # on the dual-boot layout; see config/demo.nix.
      nixosConfigurations.demo = self.lib.mkLiuqinSystem {
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
