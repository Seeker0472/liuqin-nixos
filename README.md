# liuqin-nixos — Xiaomi Pad 6 Pro (SM8475)

NixOS support for the Xiaomi Pad 6 Pro (liuqin, SM8475), built around Linux
7.2.5 and the device patches in `pkgs/kernel/patches/`.

Static vendor firmware, sensor configuration and stock boot artifacts live in
the private `liuqin-firmware-assets-OS2` repository. Builds therefore require
GitHub SSH access to that repository; `flake.lock` pins its revision and
content hash. No vendor binaries are included here, and per-device identities,
calibration, credentials and persist data stay on the tablet. Camera register
tables in patches 0012/0013 are derived driver data; see `NOTICE` for licensing
and private-data boundaries.

## Installation

The only supported first-install path boots the RAM-only NixOS installer:

```sh
nix build .#installer-bootimg --out-link result-installer
fastboot boot result-installer/boot.img
```

Do not flash this image to `boot_a` or `boot_b`. The installer deliberately
does not partition or format storage; partition creation requires measuring
the device's GPT and is an operator-reviewed, potentially destructive step.
The live USB telnet shell is an unauthenticated root channel for a directly
connected trusted host only.

See [docs/INSTALL.md](docs/INSTALL.md) for partition layouts, installation,
updates and recovery. See [docs/BOOT-ARCHITECTURE.md](docs/BOOT-ARCHITECTURE.md)
for the boot chain and generation menu.

## Build outputs

```sh
nix build .#kernel
nix build .#bootimg-kernel-only
nix build .#demo-bootimg
nix build .#installer-kernel
nix build .#installer-bootimg
nix build .#uboot
nix build .#uboot-bootimg
nix build .#ksu-return-to-uboot
nix flake check
nix run .#unit-verify
```

The unit verifier uses NixOS's assembled unit tree, including upstream units,
drop-ins and dependency links, and asks systemd to verify `default.target` and
everything it reaches. It deliberately does not start every installed optional,
template and initrd unit in one synthetic transaction. Missing dependencies or
executables in the boot transaction fail the check as well as ordering cycles.
Its fixture tests run outside the build sandbox because systemd's system-manager
analyzer needs `/run/systemd` even without a running manager. The ordinary
flake checks cover patch/config/manifest integrity, storage guards and the
fingerprint runtime's read-only firmware-path contract.

Kernel consumers can use `boot.kernelPatches` and package `.override` as in
NixOS. Board patches stay first; consumer patches follow them. Direct
`structuredExtraConfig` overrides merge over the board's initial answers.
The late board/installer fragments still enforce the built-ins needed to boot;
changing those invariants requires changing the corresponding fragment too.
The [configuration ownership guide](pkgs/kernel/CONFIGURATION.md) documents
these stages and the `liuqin-kernel-config-policy` check, which rejects
duplicate owners and undeclared transitions and produces a per-symbol report.

The GNOME posture client owns the folio's accelerometer claim while an active,
unlocked panel-only tablet session needs it. In laptop posture it reapplies the
seeded DSI landscape transform; extended desktops retain their current modes
and arrangement and are reflowed when the panel's logical dimensions change.
Mirrored layouts, and tablet posture with an external display, remain under
GNOME's control. See the [sensor notes](docs/PORTING-NOTES.md#sensors).

The GNOME lid client reads UPower's immediate `LidIsClosed` state while
logind ignores lid actions in every power/dock context. Closing the cover
locks the session and sets Mutter DPMS off; opening it restores DPMS without
unlocking. This deliberately does not suspend: it avoids logind's post-resume
holdoff and the measured suspend/re-wake loop at the cost of higher closed-cover
standby power. The keyboard driver suppresses the physical backlight while the
cover is closed without replacing the requested level.

The keyboard-folio backlight is exposed through UPower as a `0..100` LED and
the supplied GNOME Quick Settings tile mirrors the flashlight interaction:
the tile toggles it, while its submenu slider sets the level and restores the
last nonzero level after a toggle.

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
during the build.
This image has been RAM-booted on the unit many times with `fastboot boot`
without trouble; writing it to a boot partition still requires care. The build
enforces the 192 MiB boot partition limit and the observed 805306368-byte
fastboot download limit.

The installed configurations get userland from cache.nixos.org and inject
device packages from the x86_64-to-aarch64 cross set via
`injectFrom = liuqin.lib.pkgsArm`. Only per-machine derivations then need an
aarch64 executor (binfmt on an x86_64 host or the device). Optional
`crossBuild = true` avoids binfmt by cross-compiling the full closure; those
derivations are not in the binary cache.

## Use as a flake input

```nix
{
  inputs.liuqin.url = "github:Seeker0472/liuqin-nixos";
  inputs.firmwareAssets = {
    url = "git+ssh://git@github.com/Seeker0472/liuqin-firmware-assets-OS2.git?ref=main";
    flake = false;
  };
  inputs.liuqin.inputs.firmwareAssets.follows = "firmwareAssets";

  outputs = { self, liuqin, firmwareAssets }:
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

## Camera

The camera stack is opt-in through `hardware.liuqin.camera.enable`.
`autofocus.enable` adds the experimental simple-IPA AF build to PipeWire and
WirePlumber; the `cam` command remains stock, while `cam-af` uses the patched
library. The three sensors share one CSID, so only one camera can stream at a
time. WirePlumber also counts as a camera consumer.

Capture, recovery and current limitations are documented in
[docs/INSTALL.md](docs/INSTALL.md#9-camera) and
[docs/TODO/CAMERA-MAINLINE.md](docs/TODO/CAMERA-MAINLINE.md).

## Boot parameters

The installed system's board-specific `boot.kernelParams` are:

```text
qcom_q6v5_pas.slpi_auto_boot=0
rootwait
initcall_blacklist=simplefb_driver_init
earlycon=simplefb
console=tty0
firmware_class.path=/var/lib/firmware
cpuidle.governor=teo
```

The loader supplies `init=` and `root=`; NixOS also sets `loglevel=7` and
`lsm=landlock,yama,bpf`. The installer and debug profile additionally retain
`keep_bootcon`. The ABL overlay avoids registering a second ramoops region over
the one reserved by ABL. The display hand-off behavior and its remaining
U-Boot-path workaround are covered in [docs/INSTALL.md](docs/INSTALL.md) and
[`docs/BOOT-ARCHITECTURE.md`](docs/BOOT-ARCHITECTURE.md).

## Boot image construction

`pkgs/bootimg/default.nix` builds the ABL `boot.img` from the selected kernel,
ramdisk and OS2.0.4 stock device-tree inputs. It applies the ABL and
installer-specific overlays, then checks framebuffer geometry, identity
properties and the DT symbol/fixup contract before packaging.

See [docs/BOOT-ARCHITECTURE.md](docs/BOOT-ARCHITECTURE.md) for the boot flow
and `pkgs/bootimg/` for the image implementation.

## Repository map

```text
flake.nix                 package, configuration and image outputs
config/installer.nix      RAM-only live installer
config/demo/              consumer flake and example machine configuration
modules/liuqin/           installed-system hardware and initrd modules
pkgs/kernel/              Linux configuration and device patches
pkgs/bootimg/             ABL boot image and DTB construction
pkgs/u-boot/              U-Boot source port, patches and board files
```

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
