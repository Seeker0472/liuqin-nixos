# SPDX-License-Identifier: MIT
{
  description = "NixOS for Xiaomi Pad 6 Pro (liuqin, SM8475) on latest stable Linux";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      pkgsHost = import nixpkgs { system = "x86_64-linux"; };

      # x86_64 -> aarch64 cross package set carrying the liuqin overlay.
      pkgsArm = import nixpkgs {
        localSystem.system = "x86_64-linux";
        crossSystem.system = "aarch64-linux";
        overlays = [ self.overlays.default ];
        config.allowImportFromDerivation = true;
      };

      # Native aarch64 package set (for the NixOS system closure).
      pkgsNative = import nixpkgs {
        system = "aarch64-linux";
        overlays = [ self.overlays.default ];
        config.allowImportFromDerivation = true;
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
        # Host-side installer; runs on x86_64 against fastboot.
        installer = pkgsHost.writers.writePython3Bin "liuqin-install" {
          libraries = [ ];
          flakeIgnore = [ "E501" ];
        } (builtins.readFile ./tools/install.py);
      };

      nixosModules.liuqin = import ./modules/liuqin;

      nixosConfigurations.liuqin = lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = { liuqinOverlay = self.overlays.default; };
        modules = [
          {
            nixpkgs.overlays = [ self.overlays.default ];
            # requireFile payloads (firmware, SSC config) count as unfree.
            nixpkgs.config.allowUnfreePredicate = pkg:
              builtins.elem (lib.getName pkg) [
                "liuqin-ssc-config.tar.zst"
                "liuqin-firmware-touch.tar.zst"
                "liuqin-firmware-dsp.tar.zst"
                "liuqin-firmware-gpu.tar.zst"
                "liuqin-firmware-bt.tar.zst"
                "liuqin-firmware-wlan-board.tar.zst"
              ];
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
