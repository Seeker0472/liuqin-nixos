# Porting notes: xiaomipad-6pro-mainline → liuqin-nixos

Nix expression of the downstream device work, on Linux 7.2.5 (downstream is on
6.17). A downstream behaviour is a candidate to port, not proof it is safe here.

## Kernel

Twelve patches, applied in filename order:

| # | content |
|---|---|
| 0001 | DTS and bindings for SM8475/liuqin |
| 0002 | Nanosic WN8030 keyboard bridge |
| 0003 | Novatek NT36523 SPI touchscreen |
| 0004 | Novatek NT36532 DSI panel |
| 0005 | AudioReach/TDM/CS35L41 audio |
| 0006 | PON, battmgr, PMIC GLINK |
| 0007 | Iris video decoder adaptation |
| 0008 | misc, UBWC, simplefb early console |
| 0009 | I2C eUSB2 repeater |
| 0010 | SM8475 TLMM pinctrl |
| 0011 | gpio function flag in that pinctrl driver |
| 0012 | dirtyfb flush for CPU-written framebuffers |

Three config inputs:

- `kernel/config.nix` — structured answers, installed system;
- `kernel/liuqin-firstboot.config` — raw fragment appended in `postConfigure`
  for symbols a structured answer cannot settle (Kconfig question order, or
  `olddefconfig` downgrading `=y` to `=m`), then `make olddefconfig` and an
  assertion that each symbol is `=y`;
- `kernel/installer.config` — same mechanism, installer kernel only (its RAM
  image has no module tree, so the USB/HID gadget paths are built in).

The experimental DRAM-resident console patch was removed: unreliable on this
device.

## Command line

Installed system:

```text
earlycon=simplefb console=drm_log console=tty0
initcall_blacklist=simplefb_driver_init rootwait
```

`earlycon=simplefb` plus `keep_bootcon` plus `console=tty0` keep a console
alive from the first line; the console loglevel stays at the kernel default
(NixOS' `loglevel=4` hid the log). The SMMU/display-clock blacklist and the
option that enabled it (`hardware.liuqin.boot.legacySmmuDispccBlacklist`) are
gone: a configuration with those initcalls disabled crashes this unit.

`0008`'s early framebuffer clears each reused line rather than the whole
screen, so the newest screenful survives a wrap.

Ramoops: the reserved-memory node exists in the DTS, and
`dts/liuqin-abl-boot-overlay.dts` disables it, because ABL supplies the same
region in the final DT and two copies overlap.

## Display

- Panel `xiaomi,pipa-nt36532`, CSOT module `m81_42_02_0b`, `MIPI_DSI_MODE_VIDEO`,
  two DSI hosts, DPMS on, KTZ8866 backlight at 1500/2047. The DTS fallback
  `novatek/liuqin/novatek_nt36532_m81_fw_csot.bin` is correct for this unit;
  automatic TM/CSOT selection is not implemented.
- DRM client is `DRM_CLIENT_DEFAULT_FBDEV` (asserted), giving `fb0`/`msmdrmfb`
  and a getty on `tty1`. `fb0: framebuffer is not in virtual address space` is
  informational: `sys_fillrect()` warns and still calls `fb_fillrect()`.
- `0011`: the backported `pinctrl-sm8475.c` declared its gpio function with
  `MSM_PIN_FUNCTION()`, and 7.2.5's pinmux core refuses a GPIO request on a pin
  whose mux function lacks `PINFUNCTION_FLAG_GPIO`. Without
  `MSM_GPIO_PIN_FUNCTION()` the panel reset (`gpio0`), the four CS35L41 resets
  (`gpio1/3/87/92`) and the gpio-keys hall lines (`gpio10/23`) all fail.
- `0012`: the damage chain (`sys_*` → damage → `damage_work` → `fb_dirty`) ran,
  but `msm_framebuffer_dirtyfb()` returned early on
  `refcount_read(&dirtyfb) == 1`, so `drm_atomic_helper_dirtyfb()` never ran and
  console output stayed invisible until an unrelated commit. The interface is
  `INTF_MODE_VIDEO` (debugfs `encoder-0/status`, `crtc-0` `intf_mode: 2`).
  The skip now also requires that nothing has the framebuffer CPU-mapped
  (`msm_obj->vmap_count == 0`); GPU-written framebuffers are unchanged.
- `liuqin-screen-refresh` blanks/unblanks once after multi-user; that commit
  redraws the console scrollback, including what was printed before the DRM
  fbdev took over, into the framebuffer the panel scans.
- Touchscreen: the driver downloads firmware on resume, so without the payload
  above it closes the device on the first blank/unblank. The installer does not
  ship it (its panel is output-only); the installed system carries the full
  firmware set.
- The `-safe` installer profile (blacklisting `arm_smmu_init` and
  `disp_cc_sm8450_driver_init`) went white and then rebooted on this unit, and
  was removed. One installer image remains.
- The kernel's touchscreen firmware parser should validate ranges as
  `offset <= length && size <= length - offset` before checksums or copies; the
  7.2.5 adaptation does not do this yet.

## Installer

- RAM-only live root. `installer-bootimg` is the only image.
- Channel: USB2 peripheral NCM gadget at `192.168.7.2/24`, DHCP and telnet on
  `192.168.7.2:2323`, sshd on port 22. Stage 2 recreates the gadget.
- Toolchain: `sgdisk`, `parted`, `mkfs.ext4`, `e2fsck`, `resize2fs`,
  `resize.f2fs`, `mkfs.f2fs`, `nmtui`, and upstream `nixos-install`: the
  operator partitions, formats and mounts the target, and the closure reaches
  `/mnt/nix/store` either through `--substituters` or through a `nix copy` into
  the mountpoint followed by `--system <path>`. There is no liuqin wrapper
  around it; the target's own activation writes the initrd guard's marker.
- The initrd disables NixOS' generic PC module list: this kernel has UFS, SCSI,
  ext4, IOMMU and USB built in, and the generic list's absent modules
  (`ata_piix`) fail before the guard runs.
- The initrd firmware tree is at `/var/lib/firmware`, matching
  `firmware_class.path` and avoiding the read-only `/lib` symlink.

Four defects fixed to get here, each verified on the unit:

| defect | fix |
|---|---|
| `CONFIG_SQUASHFS_CHOICE_DECOMP_BY_MOUNT` unset, so mount's `loop,threads=multi` answered `EINVAL` and `/sysroot/nix/.ro-store` never mounted | set in `kernel/installer.config`, asserted |
| stage 1's `init=` lookup resolved inside `/sysroot`, and ABL appends its own `init=/init` last | `ExecStartPre` plants the marker, listed in `boot.initrd.systemd.storePaths` |
| the filtered live toplevel dropped `boot.json`, which stage 1 needs for the etc image and `env`/`modprobe` | keep `boot.json`, with `kernel`/`initrd` repointed |
| `CONFIG_EROFS_FS` unset, so the `/etc` EROFS image failed and the initrd stopped in emergency mode | enabled in `kernel/liuqin-firstboot.config`, asserted in both check loops |

Measured: gadget up at ~10 s, telnet answering during the initrd, sshd and the
telnet shell at ~30 s after switch_root, `systemctl is-system-running` =
`running` with no failed units, `/etc` on the EROFS overlay, three USB units
active.

## Storage

- `hardware.liuqin.storage.layout`: `whole-userdata` (default) or
  `linux-partition` (Android keeps userdata; NixOS owns a `linux` partition).
- The root is always `/dev/disk/by-partlabel/<name>` with label `LIUQIN_ROOT`.
  Partition numbers, starts and sizes differ between the 256 GB and 512 GB GPTs,
  so no geometry constant exists in the repository.
- The initrd guard verifies the identity (partlabel, filesystem label, and
  `/etc/liuqin-nixos-root` content, mode, owner, size and sha256), forces every
  other `sd*` node read-only, opens only the root rw and then reasserts ro on
  the siblings; `tmpfiles f+` repairs the marker and `sysroot.mount` depends on
  the guard.
- The marker bytes live in `lib/liuqin-root-marker.nix`, shared by the guard and
  by `config/installer.nix`, which writes the file after `nixos-install`.
- A oneshot grows the root filesystem with `resize2fs`.
- `/boot` is a directory on that root partition, not a partition of its own:
  NixOS' extlinux loader writes the generation list to `/boot/extlinux/
  extlinux.conf` and copies each generation's kernel, initrd and device tree
  into `/boot/nixos`. U-Boot's `sysboot` reads that one file; see
  docs/BOOT-ARCHITECTURE.md for the two device-menu entries and the load
  addresses.

## ABL DTB and symbol contract

`pkgs/bootimg.nix` applies the ABL metadata overlay, optionally the installer
USB overlay, then builds the `__symbols__` union from every stock DTBO entry and
base DTB. Every exported symbol points at the inert `liuqin-abl-overlay-sink`
node, so ABL cannot mutate a live mainline node when it force-applies stock
overlays. The sink phandle is not fixed: the build decompiles the merged DTB,
takes the largest existing `phandle`/`linux,phandle` and emits `max + 1`.

The checked-in stock archive holds 38 DTBO entries and 11 base DTBs, and the
build asserts a 1744-symbol union. The downstream analysis tree uses 44/14 and
1781 symbols from another OS build; those counts are not correctness conditions
for this archive.

## Firmware inputs

`pkgs/firmware.nix` fetches the downstream v0.1.0 release's `boot.img` by hash
and takes the firmware tree out of its ramdisk (196 files, the count the
upstream port pins). That tree is byte-identical to the archives this
repository used to require, so the kernel sees the same files. Two payloads
are not in it and stay operator inputs, registered with
`nix-store --add-fixed sha256`: the VPU image (from the official MIUI V14
extraction) and the SSC sensor config (in the release, but in three ~2 GB
rootfs volumes rather than the ramdisk). Regulatory databases come from
nixpkgs' `wireless-regdb`.

The initrd subset carries the ath11k tree, its board data and the signed
regulatory database, and nothing else; the installed system carries the whole
tree. Nothing proprietary is committed: the release is fetched by hash and the
operator inputs are `requireFile`. Two archives stay in the tree because the
release does not carry them (`data/stock-base-dtbs.nix`,
`data/stock-dtbo-entries.nix`; it ships no `vendor_boot.img`).

## Not enabled by default

- TM/CSOT automatic selection for other panel batches;
- WCD938x/SoundWire microphone capture (the four-speaker TDM path is
  implemented; the downstream 6.17 DTS also describes the capture graph);
- USB3/OTG role switching (base DTS and installer overlay both select the
  validated USB2 peripheral role);
- Xiaomi MiPPS/PPS userspace authentication (`0006` exposes the kernel transport
  and raw attributes only);
- the touchscreen firmware payload in the installer;
- re-enabling the duplicate ramoops region.

Each item needs its own kernel profile or device test, not an installer change.

## Known refactors (TODO)

- `config/installer.nix`: move `usbGadgetSetup` / `usbShellLogin` /
  `screenRefresh` (the embedded shell that remains) into `pkgs/` as
  `writeShellApplication` with `runtimeInputs`, following
  `pkgs/liuqin-power-keyd/`. The install path itself is no longer in this file:
  upstream `nixos-install` runs against the operator's mounted target.
- `modules/liuqin/initrd-guard.nix`: same treatment for the ~150-line guard
  script.
