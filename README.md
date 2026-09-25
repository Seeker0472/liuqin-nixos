# liuqin-nixos — Xiaomi Pad 6 Pro (SM8475)

NixOS support for the Xiaomi Pad 6 Pro, built around Linux 7.2.5 and the
device patches in `patches/kernel/`. The repository is private: `data/` contains
proprietary firmware and stock DT artifacts from the operator's device.

## Installation model

For the proposed persistent boot and NixOS generation-menu design, see
[docs/BOOT-ARCHITECTURE.md](docs/BOOT-ARCHITECTURE.md).

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
mkfs.ext4 -L LIUQIN_ROOT /dev/disk/by-partlabel/linux
mount /dev/disk/by-partlabel/linux /mnt
findmnt -no SOURCE,FSTYPE /mnt
findfs LABEL=LIUQIN_ROOT
```

Replace `PARTNO`, `DEVICE`, and the layout-specific partlabel after measuring
the actual tablet. The live installer deliberately never partitions or formats
the device. Once the target is mounted, run:

```sh
liuqin-install-nixos --flake /path/to/flake#configuration-name
```

The wrapper first verifies that `/mnt` is an ext4 partition with the expected
filesystem label and GPT partlabel; with `--flake` it reads those expectations
from the selected configuration. `/nix` is created by `nixos-install`; the
marker is created by the wrapper. The initrd subsequently verifies the GPT
partlabel, the filesystem label, the marker and the mounted root before opening
it read-write. It never guesses partition geometry and never writes a partition
merely by booting. The installer image is now the only installation interface;
the former host-side fastboot installer and prebuilt rootfs-image path have
been removed.

When installing from `/mnt/etc/nixos/configuration.nix` without `--flake`, the
wrapper accepts the two built-in partlabels (`linux` and `userdata`); set
`LIUQIN_EXPECTED_PARTLABEL` and, for a custom filesystem label,
`LIUQIN_EXPECTED_ROOT_LABEL` to make the preflight exact.

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
nix build .#bootimg-nixos
nix build .#installer-kernel
nix build .#installer-bootimg
nix build .#uboot            # the bootloader (u-boot-nodtb.bin + DTB)
nix build .#uboot-bootimg    # its ABL boot.img (RAM boot it first)
nix flake check
```

`installer-bootimg` is the installer artifact; its display profile keeps
ABL's framebuffer alive (`earlycon=simplefb`, `keep_bootcon`, `console=tty0`)
and hands the console over to the fbdev DRM client. `installer-kernel`
and `installer-dtb` expose its kernel and DTB separately for inspection.
`bootimg-kernel-only` is a low-level bring-up artifact with an empty ramdisk
and no `init=` command line; it is not a normal bootable NixOS system image.
`bootimg-nixos` is the normal ABL RAM-boot image for an installed system;
`demo-bootimg` is the corresponding demo artifact. `uboot` and `uboot-bootimg`
are the bootloader itself and its ABL boot.img, built entirely here (see
`u-boot/default.nix` for where the sources come from). The U-Boot path needs no
`/boot` artifact: NixOS installs its own extlinux generation list into the
target's `/boot` when the system is activated (`nixos-rebuild` runs the
loader's installer).

The ABL image keeps the downstream fixed payload offsets
(`ramdisk=0x01000000`, `dtb=0x01f00000`) because those offsets are part of
the exercised Qualcomm bootloader contract. The current installer ramdisk is
large enough that its literal range crosses the DTB offset; the build records
this as a `liuqin header-layout-warning` in `boot.img.info` and prints it
during the build. This image has since been RAM-booted on the unit many times
through `fastboot boot` without trouble; writing it to a boot partition is
still not exercised, so that remains the operation to approach deliberately. The build also enforces the 192 MiB boot
partition limit and the observed 805306368-byte fastboot download limit.

The repository's built-in installed configurations use the same x86_64→aarch64
cross package set as the installer, so their system closure and initrd can be
built on x86_64 without enabled aarch64 binfmt. Consumers of
`lib.mkLiuqinSystem` can opt into the same behavior with `crossBuild = true`;
native aarch64 builds remain available with the default `false`. The complete
desktop closure still requires the operator-supplied private `requireFile`
payloads in `data/`.

## Use as a flake input

```nix
{
  inputs.liuqin.url = "git+file:///path/to/liuqin-nixos";

  outputs = { self, liuqin }:
    let
      system = "x86_64-linux";
      machine = liuqin.lib.mkLiuqinSystem {
        modules = [ ./configuration.nix ];
        crossBuild = true;
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

`examples/demo/` is a complete consumer flake. Edit its
`configuration.nix` for users, hostname and timezone; use the BSP's
`installer-bootimg` for the first install.

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
DTS is disabled in `dts/liuqin-abl-boot-overlay.dts` because ABL already carries
the same `/reserved-memory/ramoops@a7000000` region; retaining both produces an
overlap and does not yield a usable second log channel.

The experimental DRAM-resident console has been removed. It was not proven
reliable on this device and is no longer part of the kernel, cmdline or tools.

## DTB and ABL overlay pipeline

`pkgs/bootimg.nix`:

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

Firmware inputs are operator-supplied fixed-output archives in `data/` and are
assembled by `pkgs/firmware.nix`. The installer copies the ath11k firmware,
board data and signed regulatory database into stage 1 so Wi-Fi can be brought
up before the live root is switched. The installed system carries the complete
device firmware tree.

## Repository map

```text
flake.nix                 package and image outputs
config/installer.nix      RAM-only live installer
modules/liuqin/           installed-system hardware and initrd modules
kernel/                   Linux configuration and installer profile
patches/kernel/           Linux 7.2.5 device patches (0001–0012)
pkgs/bootimg.nix          ABL boot image and DTB construction
u-boot/                   the bootloader: the port's own base tree + patches + files
                          (verify-port.sh proves the three equal the dev tree)
dts/                      ABL and installer DT overlays
data/                     private firmware and stock DT artifacts
```

Do not publish the `data/*.tar.zst` payloads. The device has no UART; for
bring-up use the framebuffer console, fastboot/U-Boot diagnostics and records
in the sibling `liuqin-dualboot` repository.
