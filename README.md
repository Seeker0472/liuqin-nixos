# liuqin-nixos — Xiaomi Pad 6 Pro (SM8475)

NixOS support for the Xiaomi Pad 6 Pro, built around Linux 7.2.5 and the
device patches in `patches/kernel/`. The repository is private: `data/` contains
proprietary firmware and stock DT artifacts from the operator's device.

## Installation model

Initial installation has one supported path:

```sh
nix build .#installer-bootimg --out-link result-installer
fastboot boot result-installer/boot.img
```

The image is RAM-only and must not be flashed to `boot_a` or `boot_b`. It is a
small NixOS live environment with:

- Wi-Fi through NetworkManager and the device's ath11k firmware;
- built-in USB/input support for a keyboard, including the Nanosic keyboard
  bridge;
- the ABL simple-framebuffer early console and tested display hand-off;
- `nixos-install`, filesystem tools and a root tty.

From the live tty, connect Wi-Fi with `nmtui` or `nmcli`, measure the device's
GPT, create or select the target partition, mount it at `/mnt`, and run:

```sh
liuqin-install-nixos --flake /path/to/flake#configuration-name
```

The wrapper invokes `nixos-install`, then writes the identity marker required by
the installed initrd. It never guesses partition geometry and never writes a
partition merely by booting. The installer image is now the only installation
interface; the former host-side fastboot installer and prebuilt rootfs-image
path have been removed.

The current dual-boot layout keeps Android in `boot_a`, creates a measured
`linux` partition at the userdata tail, and uses U-Boot from `boot_b` to load
`/boot/Image`, `/boot/initrd.img` and `/boot/liuqin.dtb`. Partition creation is
an explicit, operator-reviewed action from the live environment; no fixed
sector values are embedded in this repository.

## Build outputs

```sh
nix build .#kernel
nix build .#bootimg
nix build .#bootimg-nixos
nix build .#installer-kernel
nix build .#installer-bootimg
nix build .#installer-bootimg-safe
nix flake check
```

`installer-bootimg` is the normal first-install artifact and follows the
downstream simplefb-only display profile. `installer-bootimg-safe` is an
explicit fallback carrying the local SMMU/dispcc blacklist that was used by
the earlier bring-up workaround. `installer-kernel`
and `installer-dtb` expose its kernel and DTB separately for inspection.
`bootimg-nixos` is the normal ABL RAM-boot image for an installed system;
`demo-bootimg` and `demo-bootdir` are the corresponding demo/U-Boot artifacts.
`uboot-build` wraps the checked-in U-Boot packaging pipeline.

The kernel and boot image cross-build on x86_64. The complete aarch64 NixOS
closure and initrd need an aarch64 builder or enabled aarch64 binfmt.

## Use as a flake input

```nix
{
  inputs.liuqin.url = "git+file:///path/to/liuqin-nixos";

  outputs = { self, liuqin }:
    let
      system = "x86_64-linux";
      machine = liuqin.lib.mkLiuqinSystem {
        modules = [ ./configuration.nix ];
      };
      images = liuqin.lib.mkLiuqinBootImages machine;
    in {
      nixosConfigurations.mypad = machine;
      packages.${system}.bootimg = images.bootimg;
      packages.${system}.bootdir = images.bootdir;
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
initcall_blacklist=simplefb_driver_init,arm_smmu_init,disp_cc_sm8450_driver_init
rootwait
```

The normal installed-system profile keeps the SMMU/dispcc entries until an
actual device-side A/B test proves they are unnecessary on Linux 7.2.5. The
default live installer deliberately follows the downstream simplefb-only
profile; use `installer-bootimg-safe` if that experiment shows the earlier
white-screen behavior on this unit.

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
2. applies the installer-only USB host overlay when building
   `installer-bootimg`;
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
patches/kernel/           Linux 7.2.5 device patches (0001–0010)
pkgs/bootimg.nix          ABL boot image and DTB construction
pkgs/bootdir.nix          U-Boot /boot payload
dts/                      ABL and installer DT overlays
data/                     private firmware and stock DT artifacts
```

Do not publish the `data/*.tar.zst` payloads. The device has no UART; for
bring-up use the framebuffer console, fastboot/U-Boot diagnostics and records
in the sibling `liuqin-dualboot` repository.
