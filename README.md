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
flake.nix            outputs: packages, overlay, NixOS module, lib helpers,
                     example nixosConfiguration
overlay.nix          pkgs.liuqin* overlay (kernel, bootimg, device packages)
kernel/
  default.nix        linuxManualConfig: linux 7.2.5 + patches/kernel/*
  config.nix         structuredExtraConfig (device options, merged downstream fragments)
pkgs/
  mkbootimg.nix      AOSP mkbootimg.py at pinned commit (fetchurl, hashed)
  bootimg.nix        boot.img: Image.gz + ABL-processed DTB + initrd (ABL path)
  bootdir.nix        /boot payload for the U-Boot path: Image + initrd + a DTB
                     carrying the kernel command line
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
config/demo.nix      complete demo: GNOME + touch + network + audio + BT +
                     sensors on the U-Boot/dual-boot layout (nixosConfigurations.demo)
initramfs/           smoke-test PID 1 (busybox) + the script that packs it into
                     the cpio.gz bootimg.nix takes as `ramdisk`
dts/                 liuqin-abl-boot-overlay.dts (ABL board metadata overlay)
data/                UCM2 files, sensors patches, GSettings schema
tools/install.py     host-side fastboot installer (Python 3)
patches/kernel/      ten patches applying cleanly to linux 7.2.5
```

`packages.rootfsImage` (flake.nix) additionally builds the deployable ext4
rootfs image with nixpkgs' make-ext4-fs.

`packages.installer-bootimg` is the RAM-only installation medium. It contains
the liuqin kernel and a NixOS netboot live root in its ramdisk: the writable
root is tmpfs/overlay-backed, while the Nix store is a compressed squashfs.
It includes NetworkManager, the NixOS installer tools, and partition/filesystem
utilities. It does not include the installed-system storage guard and does not
write a partition merely by booting.

## Derivation graph

```
linux-7.2.5.tar.xz (fetchurl, hashed)
   + patches/kernel/0001..0010      -- linuxManualConfig (kernel/)
   -> pkgs.liuqinKernel             -- Image, modules, dtbs/qcom/sm8475-xiaomi-liuqin.dtb
      ^ the display recipe (kernel/liuqin-firstboot.config = the downstream
        liuqin-firstboot fragment verbatim + the patch-introduced symbols) is
        applied by the postConfigure hook in kernel/default.nix: appended to the
        generated .config and re-resolved with "make ARCH=arm64 O=$buildRoot
        olddefconfig", then asserted to be =y.  nixpkgs' own channels cannot
        carry it - see BRINGUP-LOG 53.9/53.10/53.16 in the U-Boot repo.

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

## Use from your own flake

This repository is a hardware-support layer (BSP), not your system
configuration. Keep your machine config in your own flake and reference
this one as an input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    liuqin.url = "git+file:///path/to/liuqin-nixos";
    liuqin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, liuqin }:
    let
      images = liuqin.lib.mkLiuqinImages self.nixosConfigurations.mypad;
    in
    {
      # mkLiuqinSystem injects nixosModules.liuqin, the liuqin overlay and
      # the unfree predicate for the firmware payloads; your modules carry
      # hostname/users/desktop/storage layout.
      nixosConfigurations.mypad = liuqin.lib.mkLiuqinSystem {
        modules = [ ./my-machine.nix ];
      };

      # Deployable artifacts built from YOUR configuration:
      packages.x86_64-linux = {
        bootimg = images.bootimg;          # boot.img (cross-compiled)
        rootfsImage = images.rootfsImage;  # ext4 rootfs for userdata
      };
    };
}
```

`examples/demo/` in this repository is a working consumer of exactly that
shape: its own flake, `liuqin` as a `path:` (or `git+https://`) input, no
nixpkgs input of its own (it inherits the BSP's pinned nixpkgs, so there is one
source of truth for versions), and a single `configuration.nix` to edit. Copy
that directory to start your own configuration.

`my-machine.nix` is a normal NixOS module with `hardware.liuqin.enable =
true;` plus whatever you want (users, GNOME, `hardware.liuqin.storage.*`
layout, timezone). `config/example.nix` in this repository is exactly such
a module and doubles as the smoke-test configuration behind the flake's
own packages and eval check.

`lib.mkLiuqinImages` also returns `rootMarkerCheck`; see
`lib.mkLiuqinImages` in flake.nix for the full contract.

## Build (this repository's example configuration)

```sh
nix build .#kernel          # cross-compiled x86_64 -> aarch64 (slow first time)
nix build .#bootimg         # boot.img without initrd (debug)
nix build .#bootimg-nixos   # boot.img with NixOS initrd + toplevel kernelParams
nix build .#installer-bootimg # RAM-only NixOS live installer boot.img
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

## Boot chain

Two chains are supported; `hardware.liuqin.boot.loader` picks one.

**ABL (`loader = "abl"`, default).** ABL's fastboot loads a `boot.img` from a
boot slot; the kernel command line travels in the Android boot header
(`pkgs/bootimg.nix`), and the installer writes `boot_a` plus the rootfs over
userdata (`--target userdata`). This is the path the downstream port uses.

**U-Boot (`loader = "uboot"`).** Once the U-Boot image has passed RAM
validation and is deliberately installed persistently, U-Boot in `boot_b`
loads the kernel itself:
its `boot_linux` script resolves the partition named `linux` (LUN0 of the UFS)
and `ext4load`s `/boot/Image`, `/boot/initrd.img` and `/boot/liuqin.dtb` before
calling `booti`. Nothing is written by the kernel or the bootloader except that
partition and, for A/B bookkeeping, the boot slot's GPT attributes.

Consequences of that design:

* The command line lives **inside the DTB** (`pkgs/bootdir.nix` bakes
  `/chosen/bootargs`): U-Boot only overwrites `/chosen/bootargs` when a
  `$bootargs` variable exists, and `boot_linux` deliberately leaves it unset.
  A kernel booted this way gets exactly `boot.kernelParams`.
* One flash installs everything: `.#demo-rootfsImage` contains the system *and*
  `/boot`, so `tools/install.py --target linux` writes a single partition and
  never touches `boot_a`, userdata or persist.
* Android stays bootable on `boot_a`; U-Boot's menu entry "Boot Android" only
  writes the A/B slot attributes and resets, which is what makes ABL pick that
  slot again.

**Bring-up rules (learned the hard way, see
`liuqin-dualboot/docs/SERVICE-REPORT-2026-09-20.md`).** On this device, letting
self-built code own the boot path can leave ABL unable to load *any* image
(`fastboot oem fbreason` answers `LoadImageAndAuth Fail`), and the only known
recovery is an authorized EDL flash or the service centre - no fastboot-visible
partition holds the damaged state, so no amount of re-flashing fixes it. Two
rules follow:

1. Keep slot A active. Never let a self-built image (kernel *or* bootloader) be
   the boot target just to avoid pressing a button.
2. Never leave U-Boot in an unbounded retry loop. Its `boot_linux`/menu paths
   end in `pause` for that reason, and `liuqin_ab_mark_successful()` rewrites
   both GPT copies of the boot LUN on every boot - a watchdog reset landing
   inside that commit is a plausible way to leave the two copies inconsistent.

## Install

On an x86_64 host with the device in fastboot:

```sh
nix build .#installer-bootimg --out-link result-installer
fastboot boot result-installer/boot.img
```

The command above uses stock ABL fastboot for a RAM boot only. It must not be
flashed to `boot_a` or `boot_b`. Once the live NixOS shell is up, connect Wi-Fi
with `nmtui` or `nmcli`. Partition and format the intended target explicitly,
mount its root filesystem at `/mnt`, then copy or fetch the desired NixOS
flake/configuration and run:

```sh
liuqin-install-nixos --flake /path/to/flake#configuration-name
```

The helper verifies that `/mnt` is a mounted target and delegates to
`nixos-install --root /mnt --no-channel-copy`; it never selects, formats, or
partitions a block device automatically. The live image omits the NixOS
channel to keep the ABL ramdisk within the 192 MiB boot-image limit, so a
flake URL/path or an existing `/mnt/etc/nixos/configuration.nix` is required.

For the existing host-side fastboot deployment flow:

```sh
nix build .#bootimg-nixos  # boot.img with the NixOS initrd
nix build .#rootfsImage    # pre-built ext4 rootfs image for userdata
nix build .#rootfsImageSparse  # sparse form for large fastboot transfers
nix run .#uboot-build       # build liuqin-dualboot's checked U-Boot boot.img
```

`uboot-build` is a Nix-declared host wrapper because `liuqin-dualboot` is a
separate sibling Git repository and cannot be imported into this flake in pure
evaluation. It invokes that repository's `build.sh` and `package-boota.sh`
unchanged; set `LIUQIN_WORKSPACE_ROOT` when running outside the usual
`/home/seeker/Develop/liuqin` workspace. The resulting image is for ABL RAM
boot validation only; the bring-up rules prohibit making it the persistent
`boot_b` target.

`.#rootfsImage` builds the full aarch64 NixOS closure natively; an x86_64
host needs aarch64 build capability: either `boot.binfmt.emulatedSystems =
[ "aarch64-linux" ]` (qemu binfmt) on the host, or an aarch64 remote
builder. `.#bootimg-nixos` cross-compiles the kernel and the boot.img assembly, but the
NixOS initrd it embeds is an aarch64 derivation like the rest of the closure:
without aarch64 capability it must come from a binary cache, or the build
stops there.

The dual-boot (U-Boot) layout needs only the rootfs image:

```sh
nix build .#demo-rootfsImage --out-link result-demo-rootfs
nix run .#installer -- --serial SERIAL --target linux \
    --rootfs result-demo-rootfs \
    --sha256-rootfs "$(sha256sum result-demo-rootfs | cut -d' ' -f1)" \
    --write-rootfs
```

For the sparse variant, build `.#demo-rootfsImageSparse` instead and pass its
out-link at `--rootfs`; the checksum is always the checksum of the exact file
being flashed.

It measures the `linux` partition on the unit, refuses to run if it is absent
(carving it is a separately audited `sgdisk` operation in the live image), and
never activates a slot: booting
the new system means starting U-Boot and picking "Boot Linux".

Before any backup or write, the installer also checks the target's
`max-download-size`. The raw emitted ext4 image is a normal (non-sparse)
image, so it must fit that one-payload fastboot limit as well as the measured
partition. For larger closures, use the corresponding `*ImageSparse` flake
output: AOSP fastboot resparsifies it into DATA-sized transfers, while the
installer materializes a temporary raw view for ext4 and label validation.

The first-install sequence is intentionally split so the diagnostic image is
never made the persistent boot target:

1. `fastboot boot` the smoke image from ABL (RAM only), connect to its USB
   NCM/ECM shell, and use `sgdisk --print /dev/sdX` to identify the actual
   userdata partition and tail geometry. Keep every UFS node read-only while
   measuring.
2. Before enabling any live-image write access, return to Android/recovery and
   shrink and check the encrypted F2FS userdata while it is unmounted and
   cleanly checked/replayed. The audit logs show `resize.f2fs` refusing an
   unclean image, so a mere tool invocation is not proof of success. The live
   image contains static `fsck.f2fs` and `resize.f2fs` plus the gated
   `liuqin-f2fs-shrink` wrapper. Its two-argument form is read-only; only
   `liuqin-f2fs-shrink DEVICE TARGET_SECTORS RESIZE-F2FS CLEAN-UNMOUNTED`
   may invoke the resize tool, and it still never edits GPT. A successful
   resize and clean follow-up check must be reviewed before continuing. Then save a GPT
   backup with `sgdisk --backup=/run/gpt-before.bin /dev/sdX`, explicitly run
   `enable-storage-writes LIUQIN-ENABLE-WRITES`, and use the bundled
   `liuqin-gpt-carve` helper for a measured dry run. Only after reviewing its
   backup path, userdata range and proposed `linux` range, repeat with
   `WRITE-LINUX-GPT USERDATA-FS-SHRINK-VERIFIED`. The helper verifies the old
   userdata
   geometry, preserves its type/GUID, rejects an occupied Linux number, and
   verifies the new table after `sgdisk` writes. Do not use historical sector
   values.
   The helper's backup is in the live image's `/run` (RAM); before rebooting,
   serve that directory from the diagnostic shell with
   `busybox httpd -f -p 8080 -h /run` and retrieve it from the host over
   `192.168.7.2`, then make a fresh backup immediately before the write
   invocation. Do not rely on a RAM-only backup surviving a reset.
3. Re-enter stock ABL fastboot and run the `--target linux` installer above.
   It measures the newly-created partition and flashes one ext4 image carrying
   both the NixOS closure and `/boot/{Image,initrd.img,liuqin.dtb}`.
4. RAM boot the same U-Boot image again and select `Boot Linux`; only after
   this path has been observed working should a persistent `boot_b` install be
   considered. Android remains on `boot_a` throughout these steps.

The `smoke-bootimg` output is a smaller read-only-by-default diagnostic and
partition-maintenance image for initial UFS/display checks. It includes static
`sgdisk`, `fsck.f2fs`, `resize.f2fs`, and the gated F2FS preflight wrapper, but has no automatic filesystem or
partition mutation and is not an installer;
all writes require the explicit operator token above. After
the kernel brings up the USB gadget, the host may use
`telnet 192.168.7.2 2323` (NCM/ECM, with DHCP in the initramfs) to inspect the
read-only diagnostic environment. The shell does not automatically modify
storage. If an operator intentionally needs to run a BusyBox block utility,
the transition is explicit: run
`enable-storage-writes LIUQIN-ENABLE-WRITES`; the command verifies every UFS
node became writable and performs no partitioning itself. For the actual GPT
carve, use the measured `sgdisk` commands only after saving the GPT backup and
checking the resulting table before rebooting.

The ABL layout builds a boot.img too and writes both artifacts. Explicit
out-link names avoid relying on Nix's `result`, `result-1`, ... numbering:

```sh
nix build .#bootimg-nixos --out-link result-boot
nix build .#rootfsImage --out-link result-rootfs
nix run .#installer -- --serial SERIAL --boot result-boot/boot.img \
    --rootfs result-rootfs \
    --sha256-boot "$(sha256sum result-boot/boot.img | cut -d' ' -f1)" \
    --sha256-rootfs "$(sha256sum result-rootfs | cut -d' ' -f1)" \
    --backup ./backup-dir --write-rootfs
```

The installer verifies product/unlocked/slot-A/userdata-geometry, backs up
boot_a/boot_b/persist first, flashes boot_a with the new boot image, then
flashes the ext4 rootfs image to userdata with `fastboot flash` (overwriting
the whole partition — the image carries the ext4 label `LIUQIN_ROOT` and the
`/etc/liuqin-nixos-root` guard marker the initrd storage guard requires
before mounting the root read-write). The destructive userdata erase stays
the last step. It never switches slots. It also refuses the U-Boot fastboot
endpoint (identified by its diagnostic `build` variable); image writes must be
performed from stock ABL fastboot.

**Debugging without a UART.** `tools/liuqin-readlog.py` (same tool as in
`liuqin-dualboot/tools/`) drives the two machine-readable channels the U-Boot
and kernel sides provide: `log` reads U-Boot's own console record through
`fastboot getvar con*`, and `dump` asks U-Boot to export the kernel's bootlog
ring out of DRAM (`liuqin_rdump`) so a boot that died before the panel came up
still leaves its log on the host. The kernel side of `dump` is this
repository's: patches/kernel/0011 plus the `bootlog=0x9f000000,0x100000` kernel
parameter.

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
* `storage.layout = "linux-partition"` (root in the dedicated `linux`
  partition, the dual-boot layout) is implemented and is what
  `config/demo.nix` uses; `whole-userdata` remains the ABL-layout default.
  Creating the partition itself is the explicit `sgdisk` step in the live
  image, not the installer; current U-Boot's safe profile has no generic GPT
  partition-table writer (its narrowly-scoped A/B slot metadata helper is
  separate).
* **Bring-up status (2026-09-21).** The U-Boot chain is implemented on both
  sides: U-Boot's `boot_linux` (env, no C changes needed - all required
  commands are built in), the `/boot` payload here, the `linux-partition`
  layout and the installer target. What is *not* done is a first boot of the
  demo system: the unit is awaiting a service repair after the failure
  described in `liuqin-dualboot/docs/SERVICE-REPORT-2026-09-20.md`, and the
  remaining work is on-device verification (desktop, touch, network, audio) -
  see the phase list in that report's companion notes and the todos in
  `liuqin-dualboot/docs/BRINGUP-LOG.md`.
* **On-device bring-up is tracked in the U-Boot repository**
  (`liuqin-dualboot/docs/BRINGUP-LOG.md`; §54/§58 supersede the older §53 record): the kernel
  boots under ABL's `fastboot boot` and reaches a busybox userspace; the NixOS
  cmdline now carries `initcall_blacklist=simplefb_driver_init,arm_smmu_init,disp_cc_sm8450_driver_init`
  until userspace owns the panel (those drivers reconfigure the display
  hardware ABL is still using, which is what made the screen go white mid-boot); and
  there is no rootfs yet, so without a ramdisk the kernel panics at
  `mount_root`.  `initramfs/` holds the smoke-test PID 1 used for that.
* `--target userdata` still depends on `fastboot fetch` for its pre-flash
  backup of `boot_a`/`boot_b`/`persist`, and the stock ABL fastboot does not
  implement `fetch` (measured; the U-Boot-side `fetch` was a local addition),
  so that target stops before writing anything. `--target linux` needs no
  backup and is the supported path for the dual-boot layout; the `userdata`
  target also overwrites Android's boot slot and /data by design.
