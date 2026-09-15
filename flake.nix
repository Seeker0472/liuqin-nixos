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

        # Deployable artifacts for ANY liuqin nixosConfiguration (this
        # flake's example or a consumer's own). Returns:
        #   bootimg          boot.img: configuration's kernel + NixOS initrd
        #                    + boot.kernelParams cmdline
        #   rootfsImage      pre-built ext4 rootfs of the whole closure,
        #                    for `fastboot flash userdata`
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
              bootargs = lib.concatStringsSep " " cfg.boot.kernelParams;
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
                let marker = cfg.hardware.liuqin.rootMarkerContent; in
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
                '';
            };

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
          # Host-side installer; runs on x86_64 against fastboot.
          installer = pkgsHost.writers.writePython3Bin "liuqin-install" {
            libraries = [ ];
            flakeIgnore = [ "E501" "E265" ];
          } (builtins.readFile ./tools/install.py);
        };

      nixosModules.liuqin = import ./modules/liuqin;

      # Example / smoke-test configuration (config/example.nix). Real
      # deployments define their own via lib.mkLiuqinSystem; this one backs
      # the flake's packages and eval check.
      nixosConfigurations.liuqin = self.lib.mkLiuqinSystem {
        modules = [ ./config/example.nix ];
      };

      # Everything that must at least evaluate.
      checks.x86_64-linux.eval-nixos =
        self.nixosConfigurations.liuqin.config.system.build.toplevel;
    };
}
