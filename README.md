# liuqin-nixos — Xiaomi Pad 6 Pro (SM8475)

NixOS support for the Xiaomi Pad 6 Pro, built around Linux 7.2.5 and the
device patches in `pkgs/kernel/patches/`. Every proprietary payload (firmware,
sensor configuration, stock DT artifacts) is an operator-supplied
`requireFile` input, so the tree carries no vendor binary; the camera register
tables in patches 0012/0013 are derived data that stays in-tree. See NOTICE
for both boundaries.

## Installation model

For the exercised installation, update and recovery procedure, see
[docs/INSTALL.md](docs/INSTALL.md). The boot chain and generation menu are
described in [docs/BOOT-ARCHITECTURE.md](docs/BOOT-ARCHITECTURE.md).

Initial installation has one supported path:

```sh
nix build .#installer-bootimg --out-link result-installer
fastboot boot result-installer/boot.img
```

The image is RAM-only and must not be flashed to `boot_a` or `boot_b`. It is a
small NixOS live environment with:

- Wi-Fi through NetworkManager and the device's ath11k firmware;
- a USB2 peripheral NCM control channel at `192.168.7.2`, with ECM fallback,
  DHCP and a temporary root telnet shell on port `2323`;
- the ABL simple-framebuffer early console and tested display hand-off;
- `nixos-install`, filesystem tools and a root tty.

After connecting the tablet to a Linux host, let the host obtain an address
through USB DHCP and connect to the installer shell with:

```sh
telnet 192.168.7.2 2323
```

If the host does not obtain an address automatically, assign `192.168.7.1/24`
to the host-side USB network interface (replace `<usb-if>` with the name shown
by `ip link`) and retry the same command:

```sh
sudo ip address replace 192.168.7.1/24 dev <usb-if>
telnet 192.168.7.2 2323
```

This is an unauthenticated root channel intended only for a direct, trusted
USB cable during installation.

The live environment also carries `VARIANT_ID=installer` and accepts root SSH
keys through `liuqin.lib.mkLiuqinInstallerSystem { authorizedKeys = [ ... ]; }`,
which installs them as root's `authorized_keys`. With a
key built into the image, the RAM installer is a standard NixOS installer
target: nixos-anywhere detects it from that tag and skips its kexec bootstrap
(its built-in kexec image is x86_64-only), so the documented remote flow
applies verbatim:

```sh
fastboot boot result-installer/boot.img
nixos-anywhere --flake .#mypad --target-host root@192.168.7.2
```

The target partition, labels and marker still have to satisfy the storage
guard (see below), so the partition is created and measured first as in the
manual flow; the closure is copied into the target like any other NixOS
install.

From the live tty, connect Wi-Fi with `nmtui` or `nmcli`, measure the device's
GPT, create or select the target partition, and prepare its identity before
mounting it at `/mnt`:

- `storage.layout = "linux-partition"` (the dual-boot/demo layout) requires a
  GPT partition label of `linux` and an ext4 filesystem label of `LIUQIN_ROOT`.
- `storage.layout = "whole-userdata"` (the default minimal layout) requires a
  GPT partition label of `userdata` and the same ext4 filesystem label. This
  layout consumes Android's userdata partition.

For a newly-created dual-boot partition, the relevant commands are equivalent
to:

```sh
sgdisk --change-name=PARTNO:linux /dev/DEVICE
mkfs.ext4 -O ^orphan_file -L LIUQIN_ROOT /dev/disk/by-partlabel/linux
mount /dev/disk/by-partlabel/linux /mnt
findmnt -no SOURCE,FSTYPE /mnt
findfs LABEL=LIUQIN_ROOT
```

Three things about that list. `sgdisk --change-name` only **renames** an
existing entry; it does not create one, and creating the `linux` partition
itself has no recipe in this repository yet. The stock `userdata` filesystem is
**f2fs** (`partition-type:userdata` in the ABL getvar dump), which cannot be
shrunk in place, so freeing the space means destroying Android's `/data` first
- a decision to take deliberately, not a command to paste. Any GPT write also
has to keep the `boot_a`/`boot_b` attribute bytes that ABL's slot state lives
on, keep a copy of both GPTs off the device before it touches them, and end
with a sync before any reset. And `-O ^orphan_file` is not decoration:
e2fsprogs enables that incompat feature by default and this U-Boot's ext4 does
not know it (`fs/ext4/ext4_common.c` warns "fs uses incompatible features" and
carries on), which risks read errors on the one partition U-Boot has to read.

Replace `PARTNO`, `DEVICE`, and the layout-specific partlabel after measuring
the actual tablet. The live image deliberately never partitions or formats the
device, and there is no liuqin install wrapper either: with the target mounted
at `/mnt`, the installation is plain upstream NixOS.

```sh
nixos-install --root /mnt --no-channel-copy
```

`nixos-install` fetches (or builds) the closure into `/mnt/nix/store`, sets the
system profile and installs the loader; it does not activate the target. With
`hardware.liuqin.boot.loader = "uboot"`, the loader step writes
`/boot/extlinux/extlinux.conf` plus this generation's kernel, initrd and device
tree into the `linux` partition. The initrd guard's marker file is written by
the target's first-boot activation. Point it at a configuration (`--flake
/path/to/flake#configuration-name`; `-I`, `--option`, `-j` and `--substituters`
pass through) or drop a `configuration.nix` at `/mnt/etc/nixos` first.

Decide where the closure comes from before running it: a mainline liuqin kernel
is not on `cache.nixos.org`, so without help `nixos-install` builds the whole
system on the tablet. Both ways below keep that on the host instead:

```sh
# (a) let the tablet fetch from a store the host serves
#     (`nix-serve` on the host, or an ssh-ng:// store it accepts)
tablet# nixos-install --root /mnt --no-channel-copy --flake <flake> \
          --substituters http://<host>:<port>

# (b) copy the closure into the target, then install that path
host$   nix build <flake>#nixosConfigurations.demo.config.system.build.toplevel
tablet# nix copy --from http://<host>:<port> --to /mnt --no-check-sigs /nix/store/<system>
tablet# nixos-install --root /mnt --no-channel-copy --system /nix/store/<system>
```

Check what the device menu will look for, then unmount and sync before
restarting:

```sh
sed -n '1,12p' /mnt/boot/extlinux/extlinux.conf
umount /mnt
sync
```

The initrd then verifies the GPT partlabel, the filesystem label, the marker
and the mounted root before opening it read-write. It never guesses partition
geometry and never writes a partition merely by booting. The RAM installer
image is the only installation interface; the former host-side fastboot
installer and prebuilt rootfs-image path have been removed.

The current dual-boot layout keeps Android in `boot_a`, creates a measured
`linux` partition at the userdata tail, and boots NixOS from `boot_b`'s U-Boot
through NixOS' extlinux generation list at
`/boot/extlinux/extlinux.conf` on that partition: one label per system
generation, each with its own kernel, initrd, device tree and command line, so
the device menu can boot any generation NixOS keeps. Partition creation is
an explicit, operator-reviewed action from the live environment; no fixed
sector values are embedded in this repository.

## Build outputs

```sh
nix build .#kernel
nix build .#bootimg-kernel-only
nix build .#demo-bootimg
nix build .#installer-kernel
nix build .#installer-bootimg
nix build .#uboot            # the bootloader (u-boot-nodtb.bin + DTB)
nix build .#uboot-bootimg    # its ABL boot.img (RAM boot it first)
nix flake check
nix run .#unit-verify        # systemd's ordering analysis over the demo units
```

`installer-bootimg` is the installer artifact; its display profile keeps
ABL's framebuffer alive (`earlycon=simplefb`, `keep_bootcon`, `console=tty0`)
and hands the console over to the fbdev DRM client. `installer-kernel`
and `installer-dtb` expose its kernel and DTB separately for inspection.
`bootimg-kernel-only` is a low-level bring-up artifact with an empty ramdisk
and no `init=` command line; it is not a normal bootable NixOS system image.
`demo-bootimg` is the ABL RAM-boot image for the demo configuration
(`config/demo`). `uboot` and `uboot-bootimg`
are the bootloader itself and its ABL boot.img, built entirely here (see
`pkgs/u-boot/default.nix` for where the sources come from). The U-Boot path needs no
`/boot` artifact: NixOS installs its own extlinux generation list into the
target's `/boot` during installation. Later updates run the loader script
explicitly after switching the system profile; see `docs/INSTALL.md`.

The ABL image keeps the downstream fixed payload offsets
(`ramdisk=0x01000000`, `dtb=0x01f00000`) because those offsets are part of
the exercised Qualcomm bootloader contract. The current installer ramdisk is
large enough that its literal range crosses the DTB offset; the build records
this as a `liuqin header-layout-warning` in `boot.img.info` and prints it
during the build. This image has since been RAM-booted on the unit many times
through `fastboot boot` without trouble; writing it to a boot partition
remains the operation to approach deliberately. The build also enforces the 192 MiB boot
partition limit and the observed 805306368-byte fastboot download limit.

The repository's installed configurations build natively for aarch64: their
userland closure is served by cache.nixos.org, and the device packages
(kernel, firmware, daemons) are injected from the flake's x86_64→aarch64 cross
set with `injectFrom = liuqin.lib.pkgsArm`. Only the per-machine derivations
(`/etc`, units, initrd, the images) then have to execute aarch64 code — on a
binfmt-capable x86_64 host, or on the device itself. `crossBuild = true`
remains available for hosts without binfmt, but it cross-compiles the entire
closure from source (cross derivations are in no binary cache). The complete
desktop closure still requires the operator-supplied private `requireFile`
payloads in `data/`.

## Use as a flake input

```nix
{
  inputs.liuqin.url = "github:Seeker0472/liuqin-nixos";

  outputs = { self, liuqin }:
    let
      system = "x86_64-linux";
      machine = liuqin.lib.mkLiuqinSystem {
        modules = [ ./configuration.nix ];
        injectFrom = liuqin.lib.pkgsArm;
      };
      images = liuqin.lib.mkLiuqinBootImages machine;
    in {
      nixosConfigurations.mypad = machine;
      packages.${system} = {
        bootimg = images.bootimg;
      };
      packages.${system}.installer-bootimg =
        liuqin.packages.${system}.installer-bootimg;
    };
}
```

`config/demo/` is a complete consumer flake and the repository's only
machine configuration; the BSP builds the very same `configuration.nix` as its
`demo` target. Copy it with
`nix flake init -t github:Seeker0472/liuqin-nixos` and edit
`configuration.nix` for users, hostname and timezone; use the BSP's
`installer-bootimg` for the first install.

Per-device payloads are options, not hidden requireFile steps:
`hardware.liuqin.firmware.{vpu,cs35l41}` and
`hardware.liuqin.sensors.sscConfig` take path literals
(`./liuqin-firmware-vpu.tar.zst`), and each falls back to the hash-pinned
`requireFile` archive when left null. With no SSC configuration set the sensor
stack is omitted and the module warns.

## Camera

The capture stack is opt-in through `hardware.liuqin.camera`:

- `enable` installs `v4l-utils` and libcamera, blacklists the sensor module
  and loads it late, and gates the option below.
- `autofocus.enable` (EXPERIMENTAL) applies the local libcamera AF series; it
  reaches pipewire and wireplumber, the processes that run libcamera in a GNOME
  session.

The sub-option does nothing without `enable`; the module warns rather than
fails the eval.

All three sensors share one CSID, so exactly one camera can be streamed at a
time, and nothing routes at boot (a boot-time route wedged the camera path on
2026-10-05).  libcamera's simple pipeline routes the graph itself for every
stream; for a raw CLI capture, a link reset or manual focus:

```sh
cam --stream role=raw --capture=5 --file=/tmp/frame.raw  # routes the graph itself
media-ctl -r -d /dev/media0                           # reset all links
v4l2-ctl -d "$(media-ctl -p -d /dev/media0 | grep -A3 dw9768 | grep -o '/dev/v4l-subdev[0-9]*' | head -1)" \
  --set-ctrl focus_absolute=536                       # focus while streaming
```

Probing an already-routed graph, or letting uDev autoload the sensor module in
early boot, has wedged the SoC's camera path (2026-10-05); the module is loaded
late by the `liuqin-camera-probe` oneshot (three attempts, 5 s apart), and
nothing routes at boot.

Only one consumer can hold the camera, and wireplumber's v4l2 monitor counts
as one: in a GNOME session, mask wireplumber for the session
(`systemctl --user mask wireplumber`) before a raw capture and unmask
afterwards. The desktop user must be in the `video` group -
it is what lets the software ISP open the dma-buf heaps (the module grants
`video` only the heaps libcamera actually opens).

The `cam` on `PATH` is the stock libcamera; the autofocus build is injected only
into pipewire/wireplumber (`cam-af` runs it from the command line). A plain
`cam` capture therefore verifies the stock path, not the AF path.

## Boot and display contract

The ABL image carries the command line in `/chosen/bootargs`. The normal
profile retains the empirically required display hand-off:

```text
earlycon=simplefb
console=drm_log console=tty0
initcall_blacklist=simplefb_driver_init
rootwait
```

The installed-system profile uses the downstream simplefb-only profile. The
`arm_smmu_init`/`disp_cc_sm8450_driver_init` blacklist is gone entirely: it
left IOMMU-backed UFS/PCIe/display consumers without their provider, the
installer variant carrying it crashed and was removed, and the option that
enabled it was deleted with it (see docs/PORTING-NOTES.md).

The early framebuffer implementation keeps the most recent screenful when it
wraps instead of clearing the entire display. This is deliberate: the panel is
the only pre-userspace diagnostic channel on this unit, and the last visible
lines identify where a boot stopped. The ramoops node supplied by the kernel
DTS is disabled in `pkgs/bootimg/dts/liuqin-abl-boot-overlay.dts` because ABL already carries
the same `/reserved-memory/ramoops@a7000000` region; retaining both produces an
overlap and does not yield a usable second log channel.

The experimental DRAM-resident console has been removed. It was not proven
reliable on this device and is no longer part of the kernel, cmdline or tools.

## DTB and ABL overlay pipeline

`pkgs/bootimg/default.nix`:

1. applies the ABL metadata overlay;
2. applies the installer-only USB2 peripheral overlay when building
   `installer-bootimg`; the initrd then creates the downstream-compatible
   configfs NCM gadget (falling back to ECM);
3. collects symbols referenced by all stock DTBO entries and base DTBs;
4. redirects every exported symbol to an inert sink;
5. chooses the sink phandle dynamically as `max(existing phandles) + 1`;
6. verifies the final framebuffer geometry, identity properties and symbol
   union before invoking `mkbootimg`.

The current stock archive contains 38 DTBO entries and 11 base DTBs, producing
the asserted 1744-symbol union. The downstream 1781-symbol count comes from a
different OS/DTB archive and is not an error in this input set.

## Firmware

Firmware inputs are operator-supplied fixed-output archives (`requireFile`:
local copies in `data/`, hashes in `pkgs/firmware.nix`) and are assembled by
`pkgs/firmware.nix`. The installer copies the ath11k firmware, board data and
signed regulatory database into stage 1 so Wi-Fi can be brought up before the
live root is switched. The installed system carries the complete device
firmware tree. `hardware.liuqin.firmware.{vpu,cs35l41,bootImg}` accept your
own archives and release image by path instead of a store registration, so no
build fetches from a third-party release asset.

## Repository map

```text
flake.nix                 package and image outputs
config/installer.nix      RAM-only live installer
config/demo/              the demo machine: consumer flake + configuration.nix
                          (the BSP's own `demo` target, single source)
modules/liuqin/           installed-system hardware and initrd modules
pkgs/kernel/              Linux configuration and installer profile; the 7.2.5
                          device patches live in pkgs/kernel/patches/, applied
                          in filename order (index/provenance: that README.md)
pkgs/bootimg/             ABL boot image and DTB construction, with the ABL and
                          installer DT overlays under dts/ and the stock DT
                          archive inputs (stock-*.nix, requireFile)
pkgs/u-boot/              the bootloader: the pinned base tree + patches/ + files/
data/                     local copies of the requireFile payloads (gitignored)
```

The `data/liuqin-*.tar.zst` archives and the two `pkgs/bootimg/stock-*.tar.zst`
archives are gitignored operator payloads; see `.gitignore` for registration
instructions. The device has no UART; for
bring-up use the framebuffer console and fastboot/U-Boot diagnostics.

## Acknowledgements

This port stands on other people's work — in particular the Xiaomi Pad 6 Pro
community:

- [yzddmr6/xiaomipad-6pro-mainline](https://github.com/yzddmr6/xiaomipad-6pro-mainline)
  is *Ubuntu for Xiaomi Pad 6 Pro*, the community Ubuntu port that mapped this
  board out first. The power-key daemon and the ALSA UCM card files come from
  it, the fingerprint userspace is vendored from it (PR #11, from the
  yuzelingsha fork) under `pkgs/fingerprint/fpc-oem-src/`, and the knowledge
  behind this tree's provisioning model (partition geometry, ABL behaviour,
  systemd ordering) was extracted from its work.
- [yzddmr6/linux-sm8450-liuqin](https://github.com/yzddmr6/linux-sm8450-liuqin)
  — the community liuqin kernel tree (patch 0017 is ported from its PR #7),
  forking the community SM8450 mainline effort
  [sm8450-mainline/linux](https://github.com/sm8450-mainline/linux).
- [sm8450-mainline/u-boot](https://github.com/sm8450-mainline/u-boot) — the
  U-Boot fork (`caleb/rbx-integration`) the bootloader packaging starts from.

Thanks also to the upstream projects this port patches or vendors: U-Boot and
the Linux kernel; libcamera (the autofocus IPA is a port of Raspberry Pi's
CDAF implementation, BSD-2-Clause); iio-sensor-proxy, alsa-ucm-conf,
[hexagonrpc](https://github.com/linux-msm/hexagonrpc),
[QCBOR](https://github.com/laurencelundblade/QCBOR) and
[qsee-supplicant](https://github.com/wrobelda/qsee-supplicant) (vendored);
and [NixOS/nixpkgs](https://github.com/NixOS/nixpkgs), which builds all of it.
