# Porting notes: xiaomipad-6pro-mainline → liuqin-nixos

This repository is a Nix expression of the device work in the downstream
project. The comparison is source-level: downstream currently follows a Linux
6.17 branch, while this repository reapplies the hardware changes to Linux
7.2.5. A downstream behavior is therefore a candidate to port, not proof that
the same initcall ordering is safe on 7.2.5.

## Kernel patch series

There are **ten** kernel patches, applied in filename order to Linux 7.2.5:

1. `0001` DTS and bindings for SM8475/liuqin;
2. `0002` Nanosic WN8030 keyboard bridge;
3. `0003` Novatek NT36523 SPI touchscreen;
4. `0004` Novatek NT36532 DSI panel;
5. `0005` AudioReach/TDM/CS35L41 audio;
6. `0006` PON, battmgr and PMIC GLINK;
7. `0007` Iris video decoder adaptation;
8. `0008` misc, UBWC and the simplefb early console;
9. `0009` I2C eUSB2 repeater;
10. `0010` SM8475 TLMM pinctrl.

The experimental DRAM-resident console patch was removed. It was not proven
reliable on this device and is not part of the kernel or cmdline anymore.

The downstream configuration is split into desktop, keyboard, sensors and
firstboot fragments. This tree combines the applicable options in
`kernel/config.nix` and `kernel/liuqin-firstboot.config`. The normal kernel
keeps the tested display hand-off; the installer kernel adds built-in USB and
HID options because its RAM image has no module tree.

## What is intentionally different

### Display and early console

The local `0008` implementation does not clear the whole framebuffer when it
wraps. It clears each line as it is reused, preserving the newest screenful.
That behavior is intentional because the tablet has no accessible UART and the
screen is the only early failure channel.

The normal installed-system command line remains:

```text
earlycon=simplefb console=drm_log console=tty0
initcall_blacklist=simplefb_driver_init,arm_smmu_init,disp_cc_sm8450_driver_init rootwait
```

The SMMU and display-clock blacklists are not treated as proven upstream
requirements. They remain pending an A/B test against the downstream-style
`simplefb_driver_init`-only profile on the actual device.

The default RAM installer uses that downstream-style profile so UFS/PCIe/Wi-Fi
and display initcalls are exercised together. `installer-bootimg-safe` retains
the earlier local SMMU/dispcc workaround as a rollback image if this unit still
shows the old white-screen failure.

### Ramoops

The kernel DTS contains the stock-compatible
`/reserved-memory/ramoops@a7000000`, but
`dts/liuqin-abl-boot-overlay.dts` sets that node to `status = "disabled"`.
ABL already supplies the same region when it hands the kernel its final DT;
keeping a second copy creates an overlap. This is a deliberate installer and
normal-image choice, not an omitted feature.

### Touchscreen firmware

This device is observed as panel module `m81_42_02_0b` (CSOT), so the DTS
fallback remains:

```text
novatek/liuqin/novatek_nt36532_m81_fw_csot.bin
```

The downstream driver additionally selects TM for
`m81_36_02_0a` and CSOT for `m81_42_02_0b` from the bootloader command line.
That selection should be retained when the two-panel-batch support is needed;
the fixed CSOT fallback is correct for the current unit.

The firmware parser must validate ranges as
`offset <= length && size <= length - offset` before checksums or copies.
Adding the equivalent overflow hardening to the 7.2.5 adaptation is a
correctness improvement; firmware is local input, so this is not treated as a
remote security issue.

### Audio, USB and charging

The local DTS currently implements the validated four-speaker TDM path. The
downstream 6.17 DTS also describes the WCD938x/SoundWire/LPASS microphone
capture graph; that is a separate feature to enable and test, not an installer
boot dependency.

The local base DTS remains USB2 peripheral-only. The installer image has a
separate USB-host overlay and built-in XHCI/HID support for a wired keyboard;
the normal boot image is not silently changed to an untested USB3/OTG role.

The downstream device repository's 3a9363d adds the userspace Xiaomi
MiPPS/PPS authentication daemon. Local `0006` currently exposes the kernel
transport/raw attributes only. Porting the daemon is a later normal-system
feature and must not be enabled in the installer by default.

## Installation architecture

The initial-install path is deliberately only the RAM installer image:

```text
ABL fastboot boot installer-bootimg
  → live NixOS tty/NetworkManager
  → measured partition selection/creation
  → mount /mnt
  → liuqin-install-nixos
  → nixos-install + marker provisioning
```

The former host-side fastboot installer, `fetch` backup path, pre-built
rootfs/sparse-image outputs and BusyBox diagnostic image have
been removed. This avoids maintaining two incompatible installation models and
ensures every first install has the same storage checks and marker setup.

The installed initrd still has a fail-closed storage identity guard. It checks
the configured by-partlabel device, filesystem label, root marker and UFS
read-only state before opening the target root read-write. The live installer
writes `/etc/liuqin-nixos-root` after `nixos-install`, because stage-2 tmpfiles
cannot provision a file before the first initrd probe.

## ABL DTB and symbol contract

`pkgs/bootimg.nix` applies the ABL metadata overlay, optionally applies the
installer USB overlay, then builds the `__symbols__` union from every stock
DTBO entry and base DTB. Every exported symbol is redirected to the inert
`liuqin-abl-overlay-sink` node so ABL cannot mutate a live mainline node when it
force-applies stock overlays.

The sink phandle is **not fixed**. The build decompiles the merged DTB, finds
the largest existing `phandle`/`linux,phandle`, and emits `max + 1`. This avoids
collisions when a kernel or stock DT archive gains a higher phandle.

The checked-in stock archive contains 38 DTBO entries and 11 base DTBs, and the
build asserts a 1744-symbol union. The downstream analysis tree uses 44/14 and
1781 symbols from another OS build; that count is not a correctness condition
for this archive.

## Firmware inputs

`pkgs/firmware.nix` assembles the operator-provided touch, DSP, GPU, Bluetooth,
WLAN, VPU and audio-topology archives. The installer stage-1 bundle carries the
ath11k tree, board data and signed regulatory database needed before
switch-root; the installed system carries the full tree. Proprietary archives
must not be published.

## Downstream features not yet enabled by default

- TM/CSOT automatic selection for machines other than this CSOT unit;
- WCD938x/SoundWire microphone capture;
- normal-system USB3/OTG role switching;
- Xiaomi MiPPS/PPS userspace authentication;
- removal of the SMMU/dispcc blacklists;
- re-enabling the duplicate ramoops region.

Each item needs a separate kernel/profile or device test. None should be folded
into the installer merely because it exists in the downstream 6.17 tree.
