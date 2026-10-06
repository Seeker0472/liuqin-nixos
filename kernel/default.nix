# SPDX-License-Identifier: MIT
#
# Linux 7.2.5 for Xiaomi Pad 6 Pro (liuqin, SM8475), built from the kernel.org
# tarball with the nixpkgs buildLinux generate-config flow: arm64 defconfig ->
# liuqin answers (./config.nix) -> the bring-up fragments appended after the
# generator (postConfigure below), all on the patched tree (../patches/kernel).
# nixpkgs common-config is deliberately not used; see enableCommonConfig.
#
# Note: linuxManualConfig (pkgs.linuxManualConfig) only compiles a kernel from
# an already-generated .config, so the defconfig+structured-answers flow lives
# in buildLinux, which is what this uses.  Nothing in this path is an
# ImportFromDerivation: buildLinux hands build.nix an explicit `config` and the
# generated .config is an ordinary build input, so build.nix's
# `allowImportFromDerivation` (meaningful only for linuxManualConfig /
# linuxPackages_custom) is deliberately not passed.
#
# Three config inputs, on purpose, because they answer different questions:
#   config.nix              structured answers for the installed system; they
#                           are the record of what this port wants, and they
#                           are applied in one Kconfig pass.
#   liuqin-firstboot.config raw fragment appended afterwards (see the
#                           postConfigure hook below) for the symbols that a
#                           structured answer cannot settle - either because
#                           Kconfig asks about them before their dependency,
#                           or because olddefconfig would downgrade them to
#                           =m.  Appending and re-resolving is what the
#                           downstream build script does with oldconfig.
#   installer.config        the same mechanism for the RAM installer only.
# Every "CONFIG_X=y"/"=m" line the fragments carry is asserted against the
# final .config, derived from the fragments at build time (see postConfigure),
# so a symbol that no longer resolves fails the build instead of the boot.
{ lib
, fetchurl
, buildLinux
, buildPackages
, installer ? false
, ...
}@args:

let
  version = "7.2.5";

  src = fetchurl {
    url = "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-${version}.tar.xz";
    hash = "sha256-Vd3w34Ml2drZb8/3vZOXfSLj9QrwZSdXKvWbd8djK3g=";
  };

  # Everything in ../patches/kernel, except the board DTS additions that are
  # applied after them (dtPatchNames below), so the DTS patches stay in their
  # validated order.
  commonKernelPatches =
    map
      (name: {
        name = lib.removeSuffix ".patch" name;
        patch = ../patches/kernel + "/${name}";
      })
      (builtins.sort (a: b: a < b) (
        builtins.attrNames (
          lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".patch" n)
            (builtins.readDir ../patches/kernel)
        )
      ));

  # One build carries every board feature.  The board DTS additions came from
  # three bring-up patches (usb3-device, typec-otg, dp) that cannot stack as
  # separate patches: USB3 and Type-C both add the same pm8350_l1 rail and
  # qmpphy node, and the Type-C &usb_1 hunk rewrites the node USB3 changed.
  # They are merged into one patch generated against the post-common tree, so
  # it applies without fuzz.
  # 0015 extends the same board DTS (WCD9385 capture graph), so it is applied
  # after 0014 as well.
  dtPatchNames = [
    "0014-liuqin-board-usb-typec-dp-dt.patch"
    "0015-liuqin-audio-wcd-capture.patch"
  ];

  kernelPatches =
    (lib.filter (p: !(lib.elem (baseNameOf p.patch) dtPatchNames))
      commonKernelPatches)
    ++ map (n: {
      name = lib.removeSuffix ".patch" n;
      patch = ../patches/kernel + "/${n}";
    }) dtPatchNames;

  structuredExtraConfig = import ./config.nix { inherit lib; };

  # The fragments appended by postConfigure, in append order.
  fragments = [ ./liuqin-firstboot.config ] ++ lib.optional installer ./installer.config;

  # Modules whose module-ness is load-bearing, so the generic "=m may be
  # promoted to =y" rule below must not apply to them: zram-generator
  # modprobes zram with num_devices=1, which a built-in driver never sees.
  exactModules = [ "ZRAM" ];
in
# buildLinux's generic.nix whitelists its known arguments; postBuild is not
# one of them and would be dropped silently, so the fw_path_para assertion
# is attached with overrideAttrs where every mkDerivation attr survives.
(buildLinux {
  inherit version src kernelPatches structuredExtraConfig;
  modDirVersion = version;
  # nixpkgs common-config (namespaces, cgroups, DM, CIFS/NTFS3, USB storage,
  # the sound sequencer, ...) is deliberately NOT part of the base: this
  # kernel's set is the arm64 defconfig plus the answers in ./config.nix,
  # which were derived from the downstream device configs and reviewed for
  # this port.  The price is measured, not guessed: of common-config's ~470
  # =y/=m answers, only ~180 hold here - BINFMT_MISC, USERFAULTFD,
  # KPROBES/FUNCTION_TRACER/DYNAMIC_DEBUG, ANDROID_BINDER_IPC, FS_VERITY/
  # FS_ENCRYPTION and their like are absent.  Nothing this device runs needs
  # them today; re-check that list if something does.  (config.nix was
  # deduplicated against common-config while it was still enabled, so
  # flipping this back on means re-deriving that diff.)
  enableCommonConfig = false;
  autoModules = false;
  # Modules are enabled explicitly via structuredExtraConfig; autoModules
  # would answer "m" to bool questions (PSI et al.) and wedge
  # generate-config.pl's repeated-question guard.
  # generate-config.pl treats an answer the tree never asks for - or asks
  # with a different result - as an error; keep that a warning, because a
  # consumer may add answers for symbols its tree lacks (boot.kernelPatches ->
  # structuredExtraConfig) and should not abort the build for it.  The
  # symbols this port needs are asserted against the final .config instead.
  ignoreConfigErrors = true;
  defconfig = "defconfig"; # ARCH=arm64 defconfig
}).overrideAttrs (old: {
  # Feed the downstream display recipe in where it can actually take effect.
  #
  # This hook deliberately OVERRIDES the =module choices that ./config.nix
  # still carries from the original "everything is a module, loaded from the
  # initrd/rootfs" design.  That is the one place where this derivation has two
  # sources of truth, and it is on purpose: config.nix stays the record of what
  # the flake wants for a normal (rootfs-bearing) deployment, while the recipe
  # below is the port's bring-up set for this device as it actually boots today.
  #
  # nixpkgs' own channels cannot express it: structuredExtraConfig and
  # extraConfig both end up in the one file generate-config.pl reads
  # (generic.nix: intermediateNixConfig = ... + extraConfig), and that
  # generator answers Kconfig's questions in the order Kconfig asks them -
  # so an answer that depends on another symbol being lifted first is
  # rejected.  "BT" is asked before "RFKILL" (Kconfig walks files in order),
  # so BT=y is not even offered ("ALTS: M/n/?") and the repeated-question
  # guard aborts with "Error in reading or end of file".  Writing the recipe
  # into .config and re-resolving lets the kernel solve the whole set at
  # once, which is exactly what the downstream build script does with
  # "make oldconfig"; nixpkgs' configurePhase itself runs make oldconfig
  # right before this hook, so .config is a plain file in the build tree
  # here (kconfig writes through a temp file and renames), and appending is
  # safe.  That the recipe works at all was established by hand on the host:
  # "make ARCH=arm64 oldconfig" against this kernel yields DRM_MSM=y,
  # SM_GPUCC_8450=y, SND/SND_SOC=y, QCOM_OCMEM/LLCC=y.
  postConfigure = (old.postConfigure or "") + ''
    echo "postConfigure: appending the downstream kernel config recipe"
    : "''${buildRoot:=build}"
    cat ${./liuqin-firstboot.config} >> "$buildRoot/.config"
    make ARCH=arm64 O="$buildRoot" olddefconfig
    ${lib.optionalString installer ''
      cat ${./installer.config} >> "$buildRoot/.config"
      make ARCH=arm64 O="$buildRoot" olddefconfig
    ''}
    # Check what the fragments required, derived from the same files that
    # were just appended so the expectations cannot drift from the fragments,
    # plus the frozen camera/media list in camera-symbols.txt (config.nix
    # carries those answers, but ignoreConfigErrors would let a rejected one
    # drift silently).
    # Each "CONFIG_X=y" line must survive as =y - '^CONFIG_X=' alone also
    # matches '=m', and olddefconfig silently downgrades to =m when a
    # dependency is still a module, which once left the display drivers
    # unloadable.  Each "CONFIG_X=m" line must survive as =y or =m: dropping
    # it to n is the bug (the firewall's xt-compat modules are legitimately
    # modules - nft_compat loads them on demand when a rule emulates an xt
    # match - but a missing one leaves the ruleset half applied and
    # firewall.service fails with status=4/NOPERMISSION).
    sed -n 's/^CONFIG_\([A-Za-z0-9_]*\)=\([ym]\)$/\1 \2/p' \
      ${lib.concatMapStrings (fragment: "${fragment} ") (fragments ++ [ ./camera-symbols.txt ])} \
      > "$buildRoot/fragment-symbols"
    while read -r sym want; do
      case "$want" in
        y)
          grep -qx "CONFIG_$sym=y" "$buildRoot/.config" || {
            echo "error: CONFIG_$sym is not =y in the final .config:" >&2
            grep -E "^CONFIG_$sym=|^# CONFIG_$sym is not set" "$buildRoot/.config" >&2 || echo "  (absent)" >&2
            exit 1
          }
          ;;
        m)
          grep -qE "^CONFIG_$sym=(y|m)$" "$buildRoot/.config" || {
            echo "error: CONFIG_$sym is neither =y nor =m in the final .config:" >&2
            grep -E "^CONFIG_$sym=|^# CONFIG_$sym is not set" "$buildRoot/.config" >&2 || echo "  (absent)" >&2
            exit 1
          }
          ;;
      esac
    done < "$buildRoot/fragment-symbols"
    for sym in ${lib.concatStringsSep " " exactModules}; do
      grep -qx "CONFIG_$sym=m" "$buildRoot/.config" || {
        echo "error: CONFIG_$sym is not =m in the final .config:" >&2
        grep -E "^CONFIG_$sym=|^# CONFIG_$sym is not set" "$buildRoot/.config" >&2 || echo "  (absent)" >&2
        exit 1
      }
    done
  '';
  # GNU patch does not verify the counts in "@@ -a,b +c,d @@".  A hunk that
  # declares fewer lines than it carries is applied as the declared prefix and
  # the rest is silently dropped, and the build stays green; a creation hunk
  # that drifts this way writes its file without the tail.  That is how
  # sm8475-xiaomi-liuqin.dts lost its &usb_1/&usb_1_hsphy overrides and the
  # built DTB came out with the eUSB2 PHY and DWC3 disabled - the installed
  # system then had no USB debug channel at all, while every build passed.
  # Check every patch this build consumes, so the next drift is a build
  # failure that names the hunk instead of a device that cannot be reached.
  postPatch = (old.postPatch or "") + ''
    ${buildPackages.python3}/bin/python3 ${./check-patch-hunks.py} \
      ${lib.concatMapStringsSep " " (p: "${p.patch}") kernelPatches}
    # The DP side of the combo PHY is a wholesale replacement, not a diff:
    # its values are the live register state of the vendor stack on this
    # board (Xiaomi Android 15: HBR2 4-lane, 2560x1600@60, widebus).  The
    # file is generated by liuqin-audit/kernel-exp/dp-gen-vendor-tables.py
    # plus the COM/PD_CTL fixes; it supersedes a patch because upstream
    # shares the same DP block between the sm8350 and sm8450 cfgs.
    cp ${../files/kernel/phy-qcom-qmp-combo.c} \
       drivers/phy/qualcomm/phy-qcom-qmp-combo.c
  '';
  # firmware_class.path=/var/lib/firmware (boot.kernelParams) only works when
  # the kernel was built with the fw_path_para command-line parameter; assert
  # the symbol string survived into vmlinux so a config regression fails the
  # build instead of silently breaking CS35L41 calibration loading at boot.
  postBuild = (old.postBuild or "") + ''
    echo "postBuild: asserting fw_path_para survived into vmlinux"
    strings "$buildRoot/vmlinux" | grep -q fw_path_para || {
      echo "error: vmlinux lacks fw_path_para; firmware_class.path would be a no-op" >&2
      exit 1
    }
  '';
  # Ship the *final* .config so the recipe can be diffed against the upstream
  # port's fragments instead of inferred from the build log.
  postInstall = (old.postInstall or "") + ''
    cp "$buildRoot/.config" "$out/kernel-config-final"
  '';
})
