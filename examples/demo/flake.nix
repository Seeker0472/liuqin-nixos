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
#   nix build .#bootimg         ABL path: boot.img carrying the NixOS initrd
#   nix build .#installer-bootimg RAM-only live installer (the install path)
#   nix build .#uboot-bootimg   the U-Boot boot.img (built in this repo)
#
# Evaluation needs nothing special. The example enables the BSP's
# x86_64→aarch64 cross package set, so its system and initrd can also be built
# on a normal x86_64 host. Native builds remain possible by omitting
# `crossBuild` and providing an aarch64 builder or binfmt.
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
        crossBuild = true;
      };

      # Deployable artifacts for that configuration, produced by the BSP so
      # the ABL path stays byte-compatible across consumers. The U-Boot path
      # needs no artifact: NixOS installs its own extlinux generation list.
      images = liuqin.lib.mkLiuqinBootImages configuration;
      installer = liuqin.packages.${system}.installer-bootimg;
    in
    {
      nixosConfigurations.demo = configuration;

      packages.${system} = {
        # ABL path: a boot.img (kernel + initrd + command line in the Android
        # header) for a boot slot.
        bootimg = images.bootimg;

        # The RAM installer is the only supported first-install toolchain.
        installer-bootimg = installer;
        uboot-bootimg = liuqin.packages.${system}.uboot-bootimg;
      };

      # Building this is the cheapest end-to-end proof that the configuration,
      # the module and the image wiring all evaluate.
      checks.${system}.eval = configuration.config.system.build.toplevel;
    };
}
