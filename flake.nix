# SPDX-License-Identifier: MIT
{
  description = "NixOS for Xiaomi Pad 6 Pro (liuqin, SM8475) on latest stable Linux";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      # The requireFile payloads that have no public source count as unfree.
      # The names live in pkgs/device-packages.nix, the same registry that
      # classifies the device packages, so the predicate and the payloads
      # cannot drift.  It serves the flake's own package sets and
      # mkLiuqinSystem alike.
      allowLiuqinUnfree = pkg:
        builtins.elem (lib.getName pkg) (import ./pkgs/device-packages.nix).unfree;

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

        # The flake's own x86_64->aarch64 cross package set. Pass it as
        # `injectFrom` (as the configurations below do) to reuse the device
        # artifacts it builds instead of cross-compiling the whole closure.
        inherit pkgsArm;

        # Build a liuqin NixOS configuration from consumer modules. Injects
        # the liuqin module, the package overlay and the unfree predicate;
        # the consumer's own modules carry everything else (hostname, users,
        # desktop, storage layout).
        #
        #   nixosConfigurations.mypad = liuqin.lib.mkLiuqinSystem {
        #     modules = [ ./my-machine.nix ];
        #     injectFrom = liuqin.lib.pkgsArm;
        #   };
        # The repository's own configurations use `injectFrom`: a native
        # aarch64 closure served by cache.nixos.org plus the device packages
        # built once in this flake's x86_64->aarch64 cross set, so only the
        # per-machine derivations (/etc, units, initrd) execute aarch64 code
        # (binfmt on the build host, or the device itself). `crossBuild = true`
        # remains for hosts without binfmt; it cross-compiles the entire
        # closure from source, since cross derivations are in no binary cache.
        mkLiuqinSystem =
          { modules
          , system ? "aarch64-linux"
          , crossBuild ? false
          # Re-point the device packages at an already built cross set instead
          # of building them for the target platform. This is what makes the
          # native aarch64 path affordable: the unmodified parts of the closure
          # are then served by cache.nixos.org, and the device artifacts are
          # built once, cross, and copied. See overlay-inject.nix.
          , injectFrom ? null
          }:
          lib.nixosSystem {
            inherit system;
            modules = [
              (if crossBuild then {
                # Keep the normal system on the same cross package set as the
                # RAM installer. This avoids trying to execute aarch64
                # builders on an x86_64 host with no binfmt registration.
                nixpkgs.pkgs = pkgsArm;
              } else {
                nixpkgs.overlays = [ self.overlays.default ]
                  ++ lib.optional (injectFrom != null) (import ./overlay-inject.nix { pkgsArm = injectFrom; });
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
        #
        # `authorizedKeys` puts root SSH keys into the live environment
        # (users.users.root.openssh.authorizedKeys.keys). With a key and the
        # installer's `VARIANT_ID=installer` os-release tag, nixos-anywhere
        # accepts the live environment as a standard NixOS installer and skips
        # its x86_64-only kexec image:
        #   nixos-anywhere --flake .#mypad --target-host root@192.168.7.2
        # Without keys the live shell stays reachable through the console and
        # the USB telnet channel only.
        mkLiuqinInstallerSystem =
          { modules ? [ ]
          , authorizedKeys ? [ ]
          }:
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
            ++ lib.optional (authorizedKeys != [ ]) {
              users.users.root.openssh.authorizedKeys.keys = authorizedKeys;
            }
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
            mkImage = imageBootargs: pkgsArm.callPackage ./pkgs/bootimg {
              kernel = cfg.boot.kernelPackages.kernel;
              gawk = pkgsHost.gawk;
              bootargs = lib.concatStringsSep " " imageBootargs;
              ramdisk = cfg.system.build.netbootRamdisk + "/initrd";
              extraOverlayDts = ./pkgs/bootimg/dts/liuqin-installer-overlay.dts;
            };
          in
          {
            bootimg = mkImage bootargs;
            inherit (cfg.system.build) netbootRamdisk squashfsStore toplevel;
          };

        # Build the ABL boot image for an installed configuration. The U-Boot
        # path needs nothing from here: it boots the generation list NixOS'
        # extlinux loader writes into /boot on the target. Installation itself
        # is intentionally not represented either: the only supported entry
        # point is the RAM installer image above, followed by nixos-install
        # from its live shell.
        mkLiuqinBootImages = configuration:
          let
            cfg = configuration.config;
            toplevel = cfg.system.build.toplevel;
          in
          {
            bootimg = pkgsArm.callPackage ./pkgs/bootimg {
              kernel = cfg.boot.kernelPackages.kernel;
              gawk = pkgsHost.gawk;
              bootargs = lib.concatStringsSep " " (
                cfg.boot.kernelParams ++ [ "init=${toplevel}/init" ]
              );
              ramdisk = cfg.system.build.initialRamdisk + "/initrd";
            };
          };
      };

      packages.x86_64-linux =
        let
          demoConfiguration = self.nixosConfigurations.demo;
          demoKernel = demoConfiguration.config.hardware.liuqin.package;
          installerConfiguration = self.nixosConfigurations.liuqin-installer;
          installerKernel = installerConfiguration.config.boot.kernelPackages.kernel;
          demoImages = self.lib.mkLiuqinBootImages demoConfiguration;
          installerImages = self.lib.mkLiuqinInstallerImages installerConfiguration;
        in
        {
          # Keep these outputs tied to the kernels selected by the actual
          # configurations. That makes package inspection unambiguous: the
          # demo kernel is the installed-system kernel and the installer
          # kernel is the built-in-USB variant.
          kernel = demoKernel;
          installer-kernel = installerKernel;
          dtb = pkgsArm.liuqinKernelDtb;
          installer-dtb = pkgsArm.liuqinInstallerKernelDtb;
          # Low-level bring-up artifact only: this has an empty ramdisk and
          # no `init=` command line. Use installer-bootimg or demo-bootimg
          # for a bootable NixOS environment.
          bootimg-kernel-only = pkgsArm.callPackage ./pkgs/bootimg {
            kernel = demoKernel;
            gawk = pkgsHost.gawk;
          };
          power-keyd = pkgsArm.liuqinPowerKeyd;
          mippsd = pkgsArm.liuqinMippsd;
          # Boot image for the DEMO configuration (config/demo). Your own
          # configuration: use lib.mkLiuqinBootImages instead.
          demo-bootimg = demoImages.bootimg;
          # Full NixOS live installer: kernel plus a netboot squashfs/root
          # overlay packed into the ABL boot.img ramdisk. This is the only
          # supported initial-install path and is RAM-boot-only.
          installer-bootimg = installerImages.bootimg;
          installer-ramdisk = installerImages.netbootRamdisk;
          installer-squashfs = installerImages.squashfsStore;
          # The bootloader this device boots, and the ABL boot.img built from
          # it: this is the whole U-Boot pipeline inside this flake, with no
          # sibling checkout. See pkgs/u-boot/default.nix for where the tree comes
          # from and pkgs/bootimg/default.nix for the boot.img contract (shared with
          # the kernel image).
          uboot = pkgsArm.liuqinUboot.uboot;
          uboot-bootimg = pkgsArm.liuqinUboot.bootimg;
        };

      nixosModules.liuqin = import ./modules/liuqin;

      # The demo system: the machine configuration users copy and the BSP's
      # own target. It is a plain NixOS module (config/demo/configuration.nix)
      # and the single machine file in the repository; the consumer flake next
      # to it is the same module wired through a separate flake.nix.
      #
      # Built natively for aarch64 rather than cross: the cross package set has
      # no binary-cache entries at all (a cross-built derivation is a different
      # derivation), so a cross build compiles the whole desktop from source.
      # Native aarch64 is served by cache.nixos.org, and the device packages -
      # kernel, firmware, daemons - are injected from the cross set, which is
      # built once on the x86_64 host and copied to the device. Nothing runs
      # under emulation: the remaining per-machine derivations (/etc,
      # system-path, units, initrd) are aarch64 builds that run natively on the
      # device itself.
      nixosConfigurations.demo = self.lib.mkLiuqinSystem {
        crossBuild = false;
        injectFrom = pkgsArm;
        modules = [ ./config/demo/configuration.nix ];
      };

      # RAM-only NixOS installation environment. It deliberately does not
      # import modules/liuqin, because an installer must not mount or mutate a
      # target root merely by booting.
      nixosConfigurations.liuqin-installer = self.lib.mkLiuqinInstallerSystem {
        modules = [ ./config/installer.nix ];
      };

      # Starting point for a machine configuration:
      #   nix flake init -t github:Seeker0472/liuqin-nixos
      # copies config/demo (flake.nix + configuration.nix + README.md) into the
      # current directory; the copied flake consumes this BSP as a flake input
      # and only configuration.nix needs editing.
      templates.default = {
        path = ./config/demo;
        description = "liuqin machine configuration (Xiaomi Pad 6 Pro)";
      };

      # Everything that must at least evaluate.
      checks.x86_64-linux.eval-demo =
        self.nixosConfigurations.demo.config.system.build.toplevel;
      checks.x86_64-linux.eval-installer =
        self.nixosConfigurations.liuqin-installer.config.system.build.toplevel;

      # Device-free hygiene, run by `nix flake check` on any host: no tablet,
      # no sibling checkout, no network.
      #
      # Patch hunk counts: GNU patch silently drops the tail of a hunk whose
      # @@ header understates its line count, and the build stays green
      # (pkgs/kernel/check-patch-hunks.py). The kernel build runs this over
      # pkgs/kernel/patches in postPatch; the U-Boot series has no build-time
      # equivalent, and this check covers both without building either.
      checks.x86_64-linux.liuqin-patch-hunks =
        pkgsHost.runCommand "liuqin-patch-hunks"
          { nativeBuildInputs = [ pkgsHost.python3 ]; }
          ''
            python3 ${./pkgs/kernel/check-patch-hunks.py} ${./pkgs/kernel/patches}/*.patch
            python3 ${./pkgs/kernel/check-patch-hunks.py} ${./pkgs/u-boot/patches}/*.patch
            touch $out
          '';

      # pkgs/u-boot/port.manifest pins the bytes of pkgs/u-boot/{patches,files} so
      # any hand edit there is caught here; regenerate it in the same commit (the
      # recipe is in pkgs/u-boot/default.nix). New files must be staged for the
      # flake source to carry them (the check says so when the manifest itself is
      # missing).
      checks.x86_64-linux.liuqin-uboot-port-manifest =
        pkgsHost.runCommand "liuqin-uboot-port-manifest"
          { nativeBuildInputs = [ pkgsHost.coreutils ]; }
          ''
            cd ${./pkgs/u-boot}
            if [ ! -f port.manifest ]; then
              echo "pkgs/u-boot/port.manifest is not in the flake source." >&2
              echo "A new file must be staged before it is visible: git add pkgs/u-boot/port.manifest" >&2
              exit 1
            fi
            # The pinned file set and the on-disk set must be identical ...
            find files patches -type f | LC_ALL=C sort > "$TMPDIR/current.list"
            sed 's/^[0-9a-f]\{64\}  //' port.manifest | LC_ALL=C sort > "$TMPDIR/pinned.list"
            different=$(comm -3 "$TMPDIR/pinned.list" "$TMPDIR/current.list")
            if [ -n "$different" ]; then
              echo "pkgs/u-boot/{patches,files} and port.manifest disagree on the file set:" >&2
              echo "$different" >&2
              echo "regenerate pkgs/u-boot/port.manifest (recipe in pkgs/u-boot/default.nix)" >&2
              exit 1
            fi
            # ... and every pinned hash must match.
            sha256sum -c --quiet port.manifest
            touch $out
          '';

      # The classification registry must cover overlay.nix's definitions
      # exactly, and every injected name must exist in the cross set.  A new
      # package fails this check until pkgs/device-packages.nix classifies it
      # (inject or native), which is the decision that used to be silently
      # omittable.
      checks.x86_64-linux.liuqin-package-manifest =
        let
          manifest = import ./pkgs/device-packages.nix;
          defined = builtins.attrNames (self.overlays.default pkgsHost pkgsHost);
          declared = manifest.inject ++ builtins.attrNames manifest.native;
          unclassified = lib.subtractLists defined declared;
          missing = lib.subtractLists declared defined;
          unknownInject =
            builtins.filter (n: !(builtins.hasAttr n pkgsArm)) manifest.inject;
          problems =
            lib.optional (unclassified != [ ])
              "not classified in pkgs/device-packages.nix: ${builtins.concatStringsSep " " unclassified}"
            ++ lib.optional (missing != [ ])
              "classified but not defined in overlay.nix: ${builtins.concatStringsSep " " missing}"
            ++ lib.optional (unknownInject != [ ])
              "injected but absent from the cross set: ${builtins.concatStringsSep " " unknownInject}";
        in
        pkgsHost.runCommand "liuqin-package-manifest" { }
          (
            if problems == [ ] then
              "touch $out"
            else
              ''
                echo "pkgs/device-packages.nix and overlay.nix disagree:" >&2
                ${lib.concatMapStrings (p: "echo '  ${p}' >&2\n") problems}exit 1
              ''
          );

      # The storage guard's fixture tests (fail-closed argument handling and
      # identity check, no root or block device needed) run in its checkPhase;
      # building the package here is what makes `nix flake check` execute them.
      checks.x86_64-linux.liuqin-storage-guard =
        pkgsHost.callPackage ./pkgs/storage-guard.nix { };
    };
}
