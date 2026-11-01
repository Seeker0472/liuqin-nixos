# SPDX-License-Identifier: MIT
{
  description = "NixOS for Xiaomi Pad 6 Pro (liuqin, SM8475) on latest stable Linux";

  nixConfig = {
    extra-substituters = [ "https://liuqin-nixos.cachix.org" ];
    extra-trusted-public-keys = [
      "liuqin-nixos.cachix.org-1:eZAC5Way06MN/QaQjbVZY0dnhleGCH7X7C+EUF2+Hwg="
    ];
  };

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  # Device derivations must keep one pin even when a consumer makes the
  # general nixpkgs input follow its own system revision.
  inputs.deviceNixpkgs.url = "github:NixOS/nixpkgs/eaad089433ca2bb662274377d33df3d0e51ef28b";
  inputs.firmwareAssets = {
    url = "git+ssh://git@github.com/Seeker0472/liuqin-firmware-assets-OS2.git?ref=main";
    flake = false;
  };
  # flake.lock pins the private asset repository to an exact revision and
  # content hash; authorized builders fetch it through their GitHub SSH access.

  outputs = { self, nixpkgs, deviceNixpkgs, firmwareAssets }:
    let
      lib = nixpkgs.lib;

      # Proprietary firmware/configuration/boot-data packages are unfree. Their
      # output names live in the same registry that classifies device packages,
      # so the predicate and package manifest cannot drift. This policy serves
      # the flake's package sets and mkLiuqinSystem alike.
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

      # The module injects this independently pinned package set into consumer
      # systems. A consumer may follow a newer nixpkgs for its own userland
      # without changing the device package store paths.
      pkgsNativeArm = import deviceNixpkgs {
        system = "aarch64-linux";
        overlays = [ self.overlays.default ];
        config.allowUnfreePredicate = allowLiuqinUnfree;
      };

      deviceManifest = import ./pkgs/device-packages.nix;

      # Use the cached package set for all device names in a consumer system.
      # The consumer's own nixpkgs still supplies the rest of the system.
      deviceOverlay = _final: _prev:
        builtins.listToAttrs (map (name: {
          inherit name;
          value = pkgsNativeArm.${name};
        }) (deviceManifest.inject ++ builtins.attrNames deviceManifest.native));

      # Cover the entire overlay manifest, including every output of a
      # multi-output derivation. New derivations enter the cache automatically;
      # new non-derivation values require an explicit decision here.
      cachePackages = lib.concatMap (name:
        let value = pkgsNativeArm.${name};
        in
          if lib.isDerivation value then [ { inherit name; package = value; } ]
          else if name == "liuqinUboot" then [
            { name = "liuqinUboot"; package = value.uboot; }
            { name = "liuqinUbootBootimg"; package = value.bootimg; }
          ]
          else if name == "mkLiuqinUsbGadget" then [
            {
              name = "liuqinUsbGadgetInstaller";
              package = value {
                product = "liuqin NixOS installer";
                configuration = "USB network installer";
                logToConsole = true;
                assignAddress = true;
              };
            }
            {
              name = "liuqinUsbGadgetDebug";
              package = value {
                product = "liuqin NixOS debug shell";
                configuration = "USB debug network";
                requestDeviceRole = false;
                superSpeed = true;
              };
            }
          ]
          # This is a source path consumed by the fingerprint derivations.
          else if name == "liuqinFpcOemSrc" then [ ]
          else throw "liuqin cache: unhandled overlay value ${name}"
      ) (deviceManifest.inject ++ builtins.attrNames deviceManifest.native);

      cacheLinks = lib.concatMap ({ name, package }:
        map (outputName: {
          name = "${name}-${outputName}";
          path = builtins.getAttr outputName package;
        }) (package.outputs or [ "out" ])
      ) cachePackages;
    in
    {
      overlays.default = import ./overlay.nix { inherit firmwareAssets; };

      lib = {
        inherit allowLiuqinUnfree;
        inherit pkgsNativeArm;

        # The x86_64->aarch64 cross package set remains available for builds
        # without an aarch64 executor. Its outputs differ from the native
        # device packages published in Cachix.
        inherit pkgsArm;

        # Build a liuqin NixOS configuration from consumer modules. Injects
        # the liuqin module, the package overlay and the unfree predicate;
        # the consumer's own modules carry everything else (hostname, users,
        # desktop, storage layout).
        #
        #   nixosConfigurations.mypad = liuqin.lib.mkLiuqinSystem {
        #     modules = [ ./my-machine.nix ];
        #   };
        # By default, the module injects the pinned native device packages
        # published in Cachix. Per-machine derivations (/etc, units, initrd)
        # still need an aarch64 executor (binfmt or the device). Consumers
        # without one can use `crossBuild = true`; its cross derivations have
        # different store paths and are outside the native cache.
        mkLiuqinSystem =
          { modules
          , system ? "aarch64-linux"
          , crossBuild ? false
          # Optional legacy injection for a separately built package set.
          # Leaving this null uses the module's native device cache overlay.
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
                nixpkgs.overlays = lib.optional (injectFrom != null) (import ./overlay-inject.nix { pkgsArm = injectFrom; });
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
              firmwareAssets = firmwareAssets;
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
              firmwareAssets = firmwareAssets;
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
            firmwareAssets = firmwareAssets;
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
          # Installable Android KernelSU ZIP; packaging runs on the build host.
          ksu-return-to-uboot = pkgsHost.callPackage ./pkgs/ksu-return-to-uboot { };
        };

      # One CI target that realises every native device derivation and every
      # declared output. Its symlinks also make the exact cache coverage
      # inspectable on a fresh runner after upload.
      packages.aarch64-linux.cache-closure =
        pkgsNativeArm.linkFarm "liuqin-device-cache-closure" cacheLinks;

      nixosModules.liuqin = { config, lib, ... }: {
        imports = [ ./modules/liuqin ];
        config = lib.mkIf config.hardware.liuqin.enable {
          # mkBefore lets an explicit consumer injection (such as the existing
          # x86_64 cross-built fast profile) override this native default.
          nixpkgs.overlays = lib.mkBefore [
            self.overlays.default
            deviceOverlay
          ];
        };
      };

      # The demo system: the machine configuration users copy and the BSP's
      # own target. It is a plain NixOS module (config/demo/configuration.nix)
      # and the single machine file in the repository; the consumer flake next
      # to it is the same module wired through a separate flake.nix.
      #
      # Native aarch64 userland comes from cache.nixos.org; the module injects
      # the device packages from this flake's pinned Cachix package set.
      # Per-machine derivations (/etc, system-path, units, initrd) still run
      # under binfmt on an x86_64 host or natively on the device.
      nixosConfigurations.demo = self.lib.mkLiuqinSystem {
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
      checks.x86_64-linux.liuqin-ksu-return-to-uboot =
        self.packages.x86_64-linux.ksu-return-to-uboot;

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

      # hexagonrpcd's Android-facing sns_reg_config path is backed by the
      # physical sns_reg.conf package path, while sensorspd reads a separate
      # NUL-terminated version record. Dropping either made the real DSP close
      # its FastRPC channel during activation.
      checks.x86_64-linux.liuqin-ssc-config-contract =
        let
          sensors = "${pkgsArm.liuqinSensorsConfig}/share/qcom/sm8450/Xiaomi/liuqin/sensors";
        in
        pkgsHost.runCommand "liuqin-ssc-config-contract"
          { nativeBuildInputs = [ pkgsHost.coreutils ]; }
          ''
            cmp ${sensors}/sns_reg_config ${sensors}/sns_reg.conf
            printf 'version=12\0' | cmp - ${sensors}/sns_reg_version
            touch $out
          '';

      # The package's build assertions cover firmware paths requested by the
      # board DT as well as byte identity for aliases derived from stock names.
      checks.x86_64-linux.liuqin-firmware-contract = pkgsArm.liuqinFirmware;

      # The storage guard's fixture tests (fail-closed argument handling and
      # identity check, no root or block device needed) run in its checkPhase;
      # building the package here is what makes `nix flake check` execute them.
      checks.x86_64-linux.liuqin-storage-guard =
        pkgsHost.callPackage ./pkgs/storage-guard.nix { };

      # Verify the actual NixOS default boot transaction, including upstream
      # units, package units, aliases, dependency links and drop-ins. Verifying
      # every installed optional/template/initrd unit together invents a
      # transaction NixOS never starts. An explicit unit path keeps host units
      # out while leaving store executables accessible.
      apps.x86_64-linux.unit-verify =
        let
          verifier = pkgsHost.callPackage ./pkgs/unit-verify { };
          unitTree = self.nixosConfigurations.demo.config.environment.etc."systemd/system".source;
          command = pkgsHost.writeShellScript "liuqin-demo-unit-verify" ''
            exec ${verifier}/bin/liuqin-unit-verify ${unitTree} "$@"
          '';
        in {
          type = "app";
          program = toString command;
          meta.description = "Strict verification of the demo systemd default boot transaction";
        };

      # systemd's system-manager analyzer needs /run/systemd even with
      # --root. Run its positive/negative fixtures as an app, outside the Nix
      # build sandbox, and require a real successful positive case.
      apps.x86_64-linux.unit-verify-tests =
        let
          verifier = pkgsHost.callPackage ./pkgs/unit-verify { };
          command = pkgsHost.writeShellScript "liuqin-unit-verifier-tests" ''
            exec ${pkgsHost.python3}/bin/python3 ${./pkgs/unit-verify/test_verify.py} \
              ${verifier}/bin/liuqin-unit-verify ${pkgsHost.coreutils}/bin/true
          '';
        in {
          type = "app";
          program = toString command;
          meta.description = "Positive and negative tests of the strict systemd verifier";
        };

      checks.x86_64-linux.liuqin-fingerprint-runtime =
        pkgsHost.runCommand "liuqin-fingerprint-runtime-tests" {
          nativeBuildInputs = [ pkgsHost.patch pkgsHost.python3 ];
        } ''
          cp ${./pkgs/fingerprint/fpc-oem-src/oem/oem_runtime.py} oem_runtime.py
          chmod u+w oem_runtime.py
          patch --fuzz=0 -p1 < ${./pkgs/fingerprint/oem-runtime-firmware-dir.patch}
          patch --fuzz=0 -p1 < ${./pkgs/fingerprint/oem-runtime-power-state.patch}
          python3 ${./pkgs/fingerprint/test-runtime-firmware.py} "$PWD/oem_runtime.py"
          touch $out
        '';

      checks.x86_64-linux.liuqin-kernel-config-policy =
        let
          initial = pkgsHost.writeText "liuqin-kernel-initial-answers.json"
            (builtins.toJSON (import ./pkgs/kernel/config.nix { inherit lib; }));
        in
        pkgsHost.runCommand "liuqin-kernel-config-policy" {
          nativeBuildInputs = [ pkgsHost.python3 ];
        } ''
          mkdir -p $out
          python3 ${./pkgs/kernel/check-config-policy.py} \
            --initial ${initial} \
            --board ${./pkgs/kernel/liuqin-firstboot.config} \
            --installer ${./pkgs/kernel/installer.config} \
            --camera ${./pkgs/kernel/camera-symbols.txt} \
            --policy ${./pkgs/kernel/config-transitions.json} \
            --report $out/ownership.tsv
          python3 -m unittest discover -s ${./pkgs/kernel}/tests -v
        '';

    };
}
