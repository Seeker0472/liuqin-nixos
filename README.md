# liuqin-nixos — NixOS for Xiaomi Pad 6 Pro (liuqin, SM8475)

**Private repository — do not publish.** This is the operator's personal,
self-use repository. `data/*.tar.zst` contains proprietary Qualcomm/Xiaomi
payloads (firmware, stock DTBO/base DTBs, SSC config) extracted from the
operator's own device and stock ROM dumps; they are not redistributable
(see NOTICE). If this repository is ever to be made public, first run
`git filter-repo --path-glob 'data/*.tar.zst' --invert-paths` and switch
`data/stock-dtbo-entries.nix` / `data/stock-base-dtbs.nix` back to
`requireFile` (see docs/PORTING-NOTES.md).

NixOS on the Xiaomi Pad 6 Pro with the latest stable Linux kernel
(currently 7.2.5) plus the device patch series in `patches/kernel/`,
built entirely with Nix. No downstream shell/python build scripts are used
in the build chain; Python appears only as the interpreter for mkbootimg
(boot.img assembly) and the power-menu helper, plus tools/install.py, the
host-side installer that operates the device over fastboot.

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
  firmware.nix       firmware tree (requireFile inputs, operator-supplied)
  power-keyd.nix     power-key daemon (C) + session helpers
  hexagonrpc.nix     hexagonrpc, pinned commit + liuqin patches
  libssc.nix         libssc/ssccli, pinned commit
  sensors-config.nix SSC registry/config payloads (requireFile input)
modules/liuqin/
  default.nix        hardware.liuqin options, kernel wiring, boot.kernelParams
  storage.nix        storage layout options + fileSystems generation
  initrd-guard.nix   systemd initrd storage identity guard (fail closed)
  hardware.nix       backlight/audio/WLAN/BT/sensors/Gunyah containment units
  gnome.nix          GNOME desktop policy (power-keyd, dconf, logind, dmabuf)
config/example.nix   minimal GNOME configuration (nixosConfigurations.liuqin)
dts/                 liuqin-abl-boot-overlay.dts (ABL board metadata overlay)
data/                UCM2 files, sensors patches, GSettings schema
tools/install.py     host-side fastboot installer (Python 3)
patches/kernel/      ten patches applying cleanly to linux 7.2.5
```

`packages.rootfsImage` (flake.nix) additionally builds the deployable ext4
rootfs image with nixpkgs' make-ext4-fs.

## Derivation graph

```
linux-7.2.5.tar.xz (fetchurl, hashed)
   + patches/kernel/0001..0010      -- linuxManualConfig (kernel/)
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

The proprietary payloads the build consumes are not redistributable and are
handled per-input: the stock DTBO/base DTBs used by `pkgs/bootimg.nix` are
vendored in-tree at `data/stock-{dtbo-entries,base-dtbs}.tar.zst` (private
repository — see the banner at the top), while the firmware/sensor payload
archives in `pkgs/firmware.nix` and `pkgs/sensors-config.nix` stay
`requireFile` fixed-output inputs the operator registers into the Nix store
from their own stock ROM dump; see docs/PORTING-NOTES.md. The committed
`data/liuqin-firmware-*.tar.zst` / `liuqin-ssc-config.tar.zst` are the
operator's own copies of exactly those archives; register them with
`nix-store --add-fixed sha256 data/<name>.tar.zst` to satisfy the inputs.

## Install

On an x86_64 host with the device in fastboot:

```sh
nix build .#bootimg-nixos  # boot.img with the NixOS initrd
nix build .#rootfsImage    # pre-built ext4 rootfs image for userdata
```

`.#rootfsImage` builds the full aarch64 NixOS closure natively; an x86_64
host needs aarch64 build capability: either `boot.binfmt.emulatedSystems =
[ "aarch64-linux" ]` (qemu binfmt) on the host, or an aarch64 remote
builder. `.#bootimg-nixos` cross-compiles and needs neither.

```sh
nix run .#installer -- --serial SERIAL --boot result/boot.img \
    --rootfs result-2/ext4-fs.img \
    --sha256-boot "$(sha256sum result/boot.img | cut -d' ' -f1)" \
    --sha256-rootfs "$(sha256sum result-2/ext4-fs.img | cut -d' ' -f1)" \
    --backup ./backup-dir --write-rootfs
```

The installer verifies product/unlocked/slot-A/userdata-geometry, backs up
boot_a/boot_b/persist first, flashes the ext4 rootfs image to userdata with
`fastboot flash` (overwriting the whole partition — the image carries the
ext4 label `LIUQIN_ROOT` and the `/etc/liuqin-nixos-root` guard marker the
initrd storage guard requires before mounting the root read-write), and
flashes boot_a. It never switches slots.

**Recovery:** if the initrd storage guard fails (wrong label, missing or
invalid marker, empty filesystem), the initrd has no shell by design
(`boot.initrd.systemd.emergencyAccess = false`). The only recovery channel
is fastboot: re-flash `.#rootfsImage` (and, if needed, `.#bootimg-nixos`)
with the installer.

## Open items

* `pkgs/sensors-config.nix` — the SSC config hash is pinned in
  config/example.nix; other operators must re-derive it from their own stock
  ROM dump (hardware.liuqin.sensors.sscConfigHash; see
  docs/PORTING-NOTES.md). The committed `data/liuqin-ssc-config.tar.zst` is
  the operator's own copy. The firmware payload hashes are pinned to real
  values.
* Rootfs deployment is solved: `.#rootfsImage` is a pre-built ext4 image of
  the NixOS closure (with the guard marker baked in) flashed verbatim via
  `fastboot flash userdata` — the fastboot-only equivalent of the
  downstream RAM-installer untar. There is no tarball channel; fastboot has
  no way to push a tarball for on-device extraction.
* `nix build .#kernel` is a full aarch64 kernel cross-build; expect a long
  first build. Evaluation and the small device packages are verified; the
  kernel build itself is validated by the same nixpkgs generate-config flow
  used for every nixpkgs kernel.
* `storage.layout = "custom"` (root in a userdata subpartition) is a
  reserved option that currently fails evaluation with a clear message.

