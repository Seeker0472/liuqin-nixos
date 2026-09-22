# SPDX-License-Identifier: MIT
#
# Demo system for the Xiaomi Pad 6 Pro (liuqin), built as a *consumer* of the
# BSP: this subdirectory is a flake of its own that takes ../.. as an input.
#
# liuqin-nixos is a hardware-support layer (BSP): kernel, firmware, device
# packages, the NixOS module and the image assembly. It deliberately carries no
# site configuration. This flake is the other half - the machine configuration -
# and it is what the BSP's README calls "Use from your own flake". To make it
# your own system, copy this directory elsewhere, change `inputs.liuqin.url`
# from the `path:` below to wherever your BSP checkout lives (`git+https://...`
# once it is published), and edit configuration.nix.
#
# There is deliberately no nixpkgs input of our own: the BSP's lock is the one
# source of truth, so this flake builds exactly the closure liuqin-nixos was
# developed and verified against. Update nixpkgs in the BSP (or `follows` it
# from a flake of your own) instead of tracking nixos-unstable here; two pins
# would only drift apart.
#
#   nix build .#bootdir         just the /boot payload (U-Boot path)
#   nix build .#bootimg         ABL path: boot.img carrying the NixOS initrd
#   nix build .#installer-bootimg RAM-only live installer (the install path)
#   nix run .#uboot-build       checked U-Boot RAM-boot artifact
#
# Evaluation needs nothing special. *Building* the images needs aarch64
# capability: the NixOS closure, the kernel and the initrd are aarch64
# derivations, so either
#   boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
# on the host (plus qemu binfmt), or an aarch64 builder in `--builders`. The
# kernel and the boot.img assembly also cross-compile from x86_64, but the
# initrd and the closure cannot.
{
  description = "liuqin demo machine configuration (consumer of liuqin-nixos)";

  inputs.liuqin.url = "path:../..";

  outputs = { self, liuqin }:
    let
      system = "x86_64-linux";

      # mkLiuqinSystem injects nixosModules.liuqin, the package overlay and the
      # unfree predicate for the firmware payloads; everything else comes from
      # our own modules.
      configuration = liuqin.lib.mkLiuqinSystem {
        modules = [ ./configuration.nix ];
      };

      # Deployable artifacts for that configuration. Both are produced by the
      # BSP so the ABL and U-Boot paths stay byte-compatible across consumers.
      images = liuqin.lib.mkLiuqinBootImages configuration;
      installer = liuqin.packages.${system}.installer-bootimg;
      installerSafe = liuqin.packages.${system}.installer-bootimg-safe;
    in
    {
      nixosConfigurations.demo = configuration;

      packages.${system} = {
        bootdir = images.bootdir;

        # ABL path: a boot.img (kernel + initrd + command line in the Android
        # header) for a boot slot.
        bootimg = images.bootimg;

        # The RAM installer is the only supported first-install toolchain.
        installer-bootimg = installer;
        installer-bootimg-safe = installerSafe;
        uboot-build = liuqin.packages.${system}.uboot-build;
      };

      # Building this is the cheapest end-to-end proof that the configuration,
      # the module and the image wiring all evaluate.
      checks.${system}.eval = configuration.config.system.build.toplevel;
    };
}
