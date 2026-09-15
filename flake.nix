# SPDX-License-Identifier: MIT
{
  description = "NixOS for Xiaomi Pad 6 Pro (liuqin, SM8475) on latest stable Linux";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      # requireFile payloads (firmware, SSC config) count as unfree; the same
      # predicate the nixosConfiguration carries, applied to the flake's own
      # package sets so `nix flake check` can evaluate them.
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

      # Native aarch64 package set (for the NixOS system closure).
      pkgsNative = import nixpkgs {
        system = "aarch64-linux";
        overlays = [ self.overlays.default ];
        config.allowImportFromDerivation = true;
        config.allowUnfreePredicate = allowLiuqinUnfree;
      };
    in
    {
      overlays.default = import ./overlay.nix;

      packages.x86_64-linux = {
        kernel = pkgsArm.liuqinKernel;
        dtb = pkgsArm.liuqinKernelDtb;
        bootimg = pkgsArm.liuqinBootimg;
        bootimg-nixos = pkgsArm.callPackage ./pkgs/bootimg.nix {
          kernel = self.nixosConfigurations.liuqin.config.boot.kernelPackages.kernel;
          bootargs = lib.concatStringsSep " "
            self.nixosConfigurations.liuqin.config.boot.kernelParams;
          ramdisk = self.nixosConfigurations.liuqin.config.system.build.initialRamdisk
            + "/initrd";
        };
        power-keyd = pkgsArm.liuqinPowerKeyd;
        # Pre-built ext4 rootfs image of the whole NixOS closure for
        # `fastboot flash userdata`. This is the fastboot-only replacement
        # for the downstream RAM-installer rootfs untar: the initrd storage
        # guard reads /etc/liuqin-nixos-root BEFORE sysroot is mounted, so
        # the marker must exist in the image from the start (stage-2 tmpfiles
        # only repairs it afterwards). Built on the host (e2fsprogs is
        # architecture-independent over an aarch64 closure).
        rootfsImage = pkgsHost.callPackage (nixpkgs + "/nixos/lib/make-ext4-fs.nix") {
          storePaths = [
            self.nixosConfigurations.liuqin.config.system.build.toplevel
          ];
          volumeLabel =
            self.nixosConfigurations.liuqin.config.hardware.liuqin.storage.rootLabel;
          populateImageCommands = let
            toplevel = self.nixosConfigurations.liuqin.config.system.build.toplevel;
            marker =
              self.nixosConfigurations.liuqin.config.hardware.liuqin.rootMarkerContent;
          in ''
            mkdir -p ./files/etc ./files/var ./files/tmp ./files/root ./files/home
            chmod 0755 ./files/var ./files/home ./files/etc
            chmod 1777 ./files/tmp
            chmod 0700 ./files/root
            # Dereference: environment.etc entries are store symlinks and the
            # guard requires real regular files on the rootfs.
            cp -rL ${toplevel}/etc/. ./files/etc/
            chmod -R u+w ./files/etc
            printf '%s' '${marker}' > ./files/etc/liuqin-nixos-root
            chmod 0644 ./files/etc/liuqin-nixos-root
            ln -s ${toplevel}/init ./files/init
          '';
        };
        # Host-side installer; runs on x86_64 against fastboot.
        installer = pkgsHost.writers.writePython3Bin "liuqin-install" {
          libraries = [ ];
          flakeIgnore = [ "E501" "E265" ];
        } (builtins.readFile ./tools/install.py);
        # Host-arch copy of the tmpfiles marker byte-consistency check from
        # modules/liuqin/initrd-guard.nix: runs the exact systemd.tmpfiles
        # rule through systemd-tmpfiles --create --root and requires the
        # result to be byte-identical to the guard marker. Also asserted
        # into the aarch64 system closure via an activation script.
        root-marker-check =
          self.nixosConfigurations.liuqin.config.hardware.liuqin.rootMarkerCheck
            pkgsHost;
      };

      nixosModules.liuqin = import ./modules/liuqin;

      nixosConfigurations.liuqin = lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = { liuqinOverlay = self.overlays.default; };
        modules = [
          {
            nixpkgs.overlays = [ self.overlays.default ];
            nixpkgs.config.allowUnfreePredicate = allowLiuqinUnfree;
          }
          self.nixosModules.liuqin
          ./config/example.nix
        ];
      };

      # Everything that must at least evaluate.
      checks.x86_64-linux.eval-nixos =
        self.nixosConfigurations.liuqin.config.system.build.toplevel;
    };
}
