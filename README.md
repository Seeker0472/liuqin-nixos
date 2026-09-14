# liuqin-nixos — NixOS for Xiaomi Pad 6 Pro (liuqin, SM8475)

NixOS on the Xiaomi Pad 6 Pro with the latest stable Linux kernel
(currently 7.2.5) plus the device patch series in `patches/kernel/`,
built entirely with Nix. No downstream shell/python build scripts are used
in the build chain; the only Python is `tools/install.py`, the host-side
installer that operates the device over fastboot.

## Repository layout

```
flake.nix            outputs: packages, overlay, NixOS module, nixosConfiguration
overlay.nix          pkgs.liuqin* overlay (kernel, bootimg, device packages)
kernel/
  default.nix        linuxManualConfig: linux 7.2.5 + patches/kernel/*
  config.nix         structuredExtraConfig (device options, merged downstream fragments)
pkgs/
  mkbootimg.nix      AOSP mkbootimg.py at pinned commit (fetchurl, hashed)
  bootimg.nix        boot.img: Image.gz + ABL-processed DTB + initrd
  firmware.nix       firmware tree (requireFile placeholders, operator-supplied)
  power-keyd.nix     power-key daemon (C) + session helpers
  hexagonrpc.nix     hexagonrpc, pinned commit + liuqin patches
  libssc.nix         libssc/ssccli, pinned commit
  sensors-config.nix SSC registry/config payloads (requireFile placeholder)
modules/liuqin/
  default.nix        hardware.liuqin options, kernel wiring, boot.kernelParams
  storage.nix        storage layout options + fileSystems generation
  initrd-guard.nix   systemd initrd storage identity guard (fail closed)
  hardware.nix       backlight/audio/WLAN/BT/sensors/Gunyah containment units
  gnome.nix          GNOME desktop policy (power-keyd, dconf, logind, dmabuf)
config/example.nix   minimal GNOME configuration (nixosConfigurations.liuqin)
dts/                 liuqin-abl-boot-overlay.dts (ABL board metadata overlay)
data/                UCM2 files, sensors patches, GSettings schema
tools/install.py     host-side fastboot installer (the only Python)
patches/kernel/      eight patches applying cleanly to linux 7.2.5
```

## Derivation graph

```
linux-7.2.5.tar.xz (fetchurl, hashed)
   + patches/kernel/0001..0008      -- linuxManualConfig (kernel/)
   -> pkgs.liuqinKernel             -- Image, modules, dtbs/qcom/sm8475-xiaomi-liuqin.dtb

sm8475-xiaomi-liuqin.dtb
   + dts/liuqin-abl-boot-overlay.dts        (dtc -@ + fdtoverlay)
   + __symbols__ union overlay              (synthesized from stock DTBO/base
                                             DTB fixed-output inputs, pure dtc)
   -> pkgs.liuqinBootimg (pkgs/bootimg.nix) -- mkbootimg header v2,
                                               unpack-roundtrip verified

pkgs.liuqinKernel + liuqinFirmware + overlay device packages
   -> nixosConfigurations.liuqin (config/example.nix)
   -> .#bootimg-nixos (boot.img with the NixOS initrd and cmdline)
```

## Build

```sh
nix build .#kernel          # cross-compiled x86_64 -> aarch64 (slow first time)
nix build .#bootimg         # boot.img without initrd (debug)
nix build .#bootimg-nixos   # boot.img with NixOS initrd + toplevel kernelParams
nix eval .#nixosConfigurations.liuqin.config.system.build.toplevel.drvPath
nix flake check             # evaluates everything above
```

The fixed-output inputs for the stock DTBO/base DTBs (`pkgs/bootimg.nix`)
and the proprietary firmware/sensor payloads (`pkgs/firmware.nix`,
`pkgs/sensors-config.nix`) are placeholders until an operator supplies the
archives from their own stock ROM dump; see docs/PORTING-NOTES.md.

## Install

On an x86_64 host with the device in fastboot:

```sh
nix run .#installer -- --serial SERIAL --boot result-bootimg/boot.img \
    --rootfs rootfs.tar.gz --backup ./backup-dir --write-rootfs
```

The installer verifies product/unlocked/slot-A/userdata-geometry, backs up
boot_a/boot_b/persist first, formats userdata as ext4 `LIUQIN_ROOT`, and
flashes boot_a. It never switches slots.

## Open items

* Placeholder hashes: `pkgs/bootimg.nix` (stock DTBO/base DTB sets),
  `pkgs/firmware.nix`, `pkgs/sensors-config.nix` — fill after producing
  the operator-supplied archives (see docs/PORTING-NOTES.md).
* The installer formats userdata but does not yet untar the rootfs into it
  (the downstream flow untarred inside a RAM installer; the fastboot-only
  equivalent is `fastboot flash` of a sparse ext4 image, TODO).
* `nix build .#kernel` is a full aarch64 kernel cross-build; expect a long
  first build. Evaluation and the small device packages are verified; the
  kernel build itself is validated by the same nixpkgs generate-config flow
  used for every nixpkgs kernel.
* `storage.layout = "custom"` (root in a userdata subpartition) is a
  reserved option that currently fails evaluation with a clear message.

