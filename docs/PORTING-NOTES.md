# Porting notes: xiaomipad-6pro-mainline -> liuqin-nixos

This repo re-expresses the downstream project's device adaptation in Nix.
Nothing from the downstream build system is executed; facts and data files
were extracted and re-encoded. This file records what was inherited, what
was dropped, and why.

## Kernel patch series (patches/kernel/)

Ten patches, applied in filename order on linux 7.2.5:

* 0001 DTS + bindings (sm8475.dtsi, sm8475-xiaomi-liuqin.dts)
* 0002 HID nanosic keyboard cover
* 0003 Novatek NT36523 SPI touchscreen; irq GPIO via
  fwnode_gpiod_get_index(of_fwnode_handle(np), "novatek,irq") because the
  DT carries the legacy "novatek,irq-gpio" spelling gpiod_get() cannot
  resolve (v7.2.5 removed linux/of_gpio.h, so of_get_named_gpio() is not
  available)
* 0004 Novatek NT36532 DSI panel
* 0005 AudioReach/TDM/CS35L41/sc8280xp sound
* 0006 PON/battmgr/PMIC glink
* 0007 iris video decoder for SM8450 (vpu20_4v firmware;
  .resume_without_payload = true, matching downstream
  iris_platform_gen2.c — Iris2 firmware predates the RESUME payload).
  Clock contract checked: the sm8450 platform data reuses the 3-entry
  sm8550_clk_table (iface/core/vcodec0_core), and the DTS iris node
  supplies exactly those three clocks, so iris_get_clk_by_type() matches
  every entry — no -EINVAL on enable. (devm_clk_bulk_get_all() takes
  whatever the DT provides, so a 2-clock DTS would not -ENOENT at probe;
  it would instead fail later at clock-enable for the missing type.)
* 0008 misc: of/ubwc/earlycon-simplefb
* 0009 I2C eUSB2 repeater backport
* 0010 pinctrl-sm8475 TLMM (verbatim from linux-sm8450-liuqin, GPL-2.0);
  without it "qcom,sm8475-tlmm" never probes and every GPIO-backed device
  defers forever. kernel/config.nix answers PINCTRL_SM8475=y, and
  kernel/default.nix sets ignoreConfigErrors because generate-config.pl
  runs against the pristine tarball where the option does not exist yet.

## Inherited (re-expressed in Nix)

| Downstream source | liuqin-nixos expression |
|---|---|
| device/configs/liuqin-{desktop,keyboard,sensors,firstboot}.config | kernel/config.nix structuredExtraConfig (merged, deduplicated; snap-only entries dropped) |
| tools/fetch-aosp-mkbootimg.sh (commit + hashes) | pkgs/mkbootimg.nix (fetchurl + per-file sha256 checks) |
| tools/lib/build-bootimg.sh DTB pipeline | pkgs/bootimg.nix: dtc -@ + fdtoverlay for the ABL metadata overlay |
| tools/lib/abl-symbols.py (__symbols__ union, sink node) | pkgs/bootimg.nix: same decode/splice/recompile with dtc text round-trip, plus an fdtoverlay-compatible __symbols__ overlay; verified with dtc 1.7.2 that fdtoverlay preserves __symbols__. No Python in the build. |
| device/liuqin-abl-boot-overlay.dts | dts/liuqin-abl-boot-overlay.dts (verbatim, GPL) |
| device/native-bootargs.txt | boot.kernelParams defaults in modules/liuqin/default.nix; debug flags gated behind hardware.liuqin.boot.debug (default off) |
| initramfs/init storage identity check (1216-line shell) | modules/liuqin/initrd-guard.nix: one systemd initrd oneshot with the same geometry/label checks (sda 493854720 512-byte sectors, sda35 start 22065152 size 471789528, PARTNAME=userdata, LIUQIN_ROOT label, read-only lock of all other sd* nodes, ro,noload probe mount, root marker) |
| liuqin-hide-gunyah-node.service | hardware.nix systemd unit (bind-mount empty dir over /sys/firmware/devicetree/base/hypervisor) |
| logind.conf.d/90-liuqin.conf | services.logind.settings.Login (HandlePowerKey/LongPress = ignore) |
| device/power-key/liuqin-power-keyd.c | pkgs/power-keyd.nix (C build in Nix) + helpers |
| liuqin-backlight-default.service | hardware.nix systemd unit (same 1500/2047 readback assertions) |
| liuqin-wlan-mac / liuqin-bt-public-addr | hardware.nix oneshot units; identity files under /var/lib/liuqin-private, provisioned read-only from persist by liuqin-persist-provision.service (same checks: metadata 600:0:0, format, reserved/multicast rejection, fail closed) |
| device/gnome-overlay/usr/share/alsa/ucm2 | data/ucm2 + alsa-ucm-conf override in overlay.nix |
| device/sensors/patches + sources.manifest | data/sensors-patches (6 patch files) + pkgs/{hexagonrpc,libssc}.nix at pinned commits; hexagonrpc.nix applies 0001/0002 (hexagonrpcd), overlay.nix applies 0003-0006 to iio-sensor-proxy |
| sensors-overlay systemd units | hardware.nix: liuqin-slpi, liuqin-hexagonrpcd-sdsp (same sandboxing), liuqin-ssc-sample-gate (4 bounded ssccli attempts), liuqin-sensor-proxy-refresh, sysusers/tmpfiles/udev rules |
| environment.d/50-liuqin-dmabuf.conf | environment.sessionVariables in gnome.nix |
| dconf db/local.d and gdm.d | environment.etc dconf fragments in gnome.nix |
| chrony no-RTC escape hatch | services.chrony.extraConfig in default.nix |
| install-liuqin.py device checks | tools/install.py (rewritten, see below) |

## Dropped, and why

* **snapd support (liuqin-snap.config, liuqin-snap-root-admission)** —
  NixOS has no snap; the config fragment and admission service do not apply.
* **charger-mode diversion** — the downstream charger-mode path is Android
  UX compatibility; NixOS root has no charger-mode consumer. The backlight
  helper retains its `androidboot.mode=charger` guard as a safety net.
* **The 1216-line busybox init** — replaced by NixOS systemd initrd with
  one guard service. The boot RAM installer channel (telnet/USB ECM) has
  no NixOS equivalent; installation is fastboot-only.
* **abl-symbols.py / abl-dtb02-ids.py (Python in the build chain)** —
  replaced by dtc text round-trip + fdtoverlay. The stock-IDs mirror mode
  (ABL_DTB02_IDS) is not ported; the declared liuqin identity is the
  default and stock-ids mode was an experiment branch.
* **liuqin-gnome-usb-rescue / liuqin-shell / snap rescue tooling** —
  unauthenticated rescue shells are out of scope; openssh over WLAN is the
  supported remote access.
* **Ubuntu-specific units (chrony conf.d paths, flash-kernel, polkit
  rules)** — NixOS equivalents are generated by the module system.
* **build-liuqin-image.py bundle format** — the flake outputs
  (.#bootimg-nixos, .#rootfsImage) are the bundle; tools/install.py takes
  them directly.

## tools/install.py vs install-liuqin.py

Kept: product/unlocked/slot checks, userdata geometry gate
(471789528*512), boot partition size gate, backup-before-flash, serial
binding, checksum verification of every input before flashing, never
switching slots.

Changed: the downstream installer boots a RAM installer over `fastboot
boot` and untars the rootfs inside it over telnet/USB networking. That
requires the downstream initramfs, and fastboot itself has no channel to
push a tarball for on-device extraction. This repo's installer is
fastboot-only end to end, and validates its inputs before touching the
device: boot.img must carry the ANDROID! magic and fit boot_a, the rootfs
image must fit userdata, be an ext4 image and carry the LIUQIN_ROOT
volume label (parsed from superblock offset 0x478, pure Python):

* rootfs deployment: `nix build .#rootfsImage` produces a pre-built ext4
  image (nixpkgs make-ext4-fs) of the full NixOS closure, with the
  `/etc/liuqin-nixos-root` guard marker baked in at image build time (the
  initrd guard reads it before sysroot is mounted, so stage-2 tmpfiles can
  only ever repair it, never provision it). The installer flashes it
  verbatim with `fastboot flash userdata`; the image carries the
  `LIUQIN_ROOT` label, so no `fastboot format` step is needed. On first
  boot `liuqin-growfs-root.service` runs resize2fs once to grow the
  filesystem to fill the userdata partition (the image is only as large as
  the closure). rootfsImage builds the aarch64 closure natively — an
  x86_64 host needs qemu binfmt (`boot.binfmt.emulatedSystems =
  [ "aarch64-linux" ]`) or an aarch64 remote builder.
* backups use `fastboot fetch` and stop cleanly if the bootloader lacks
  it. Truncation is caught by comparing the fetched size against the
  reported partition size; that is weaker than the downstream flow, which
  also sha256-verifies every fetched partition against a manifest. The
  fetched images are still hashed into SHA256SUMS after the fact, so any
  corruption is at least detectable later, but a silent in-transit
  corruption would be backed up as-is.
* guard-failure recovery: on a guard failure the initrd drops to
  emergency.target with `emergencyAccess = false` — deliberately no root
  shell, since that would sidestep the storage identity checks. The guard
  prints explicit instructions (re-flash the rootfs image over fastboot),
  and a correctly-labelled but empty userdata gets a dedicated message.
  Re-flashing over fastboot is the ONLY recovery channel; keep a host
  with fastboot access available before installing.

## Sink phandle and __symbols__ semantics

pkgs/bootimg.nix synthesizes the __symbols__ union overlay with an inert
sink node `liuqin-abl-overlay-sink` carrying `phandle = <0xdead0000>`.
That phandle is never dereferenced: ABL resolves its overlay fixups
through the __symbols__ string table (label -> node path) only, and never
walks the sink node. Semantic difference from downstream abl-symbols.py:
labels the base DTB already exports keep pointing at their real nodes in
the nix build, while the downstream tool points every symbol at the sink.
This is safe because the symbol table only tells ABL *where* each label
lives; pointing a label at its true node is strictly more accurate than
pointing it at a sink, and the runtime Gunyah RM DTBO only needs its
fixups to resolve, not to find meaningful content behind them. The final
DTB carries 2139 __symbols__ entries (570 pointing at their real node,
1569 at the sink) and the build asserts every one of the 1744 union
symbols resolves.

## Proprietary payload inputs (not redistributable)

This repository is private / self-use only; do not publish it. The
operator's own extracted payloads are vendored in-tree under data/ (see
NOTICE). To make the repository public later: `git filter-repo
--path-glob 'data/*.tar.zst' --invert-paths`, switch
data/stock-dtbo-entries.nix / data/stock-base-dtbs.nix back from
`builtins.path` to `requireFile`, and regenerate every payload from your
own stock dump as described below.

* pkgs/firmware.nix (all hashes pinned, `requireFile` inputs — the
  operator registers the vendored data/liuqin-firmware-*.tar.zst into the
  Nix store with `nix-store --add-fixed sha256`): touch
  (novatek_nt36532_m81_fw_{csot,tm}.bin), DSP (adsp/cdsp/slpi .mbn set),
  GPU (a730_zap.mbn, a730_sqe.fw, gmu_gen70000.bin), BT (BTFM set), WLAN
  board data (board data + updates/ amss tuples), VPU (qcom/vpu/
  vpu20_4v.mbn, iris2 firmware for patch 0007), audio topology, and
  regulatory.db{,.p7s} (taken from nixpkgs linux-firmware, redistributable).
  The kernel-requested contract paths are asserted at build time:
  novatek/liuqin/novatek_nt36532_m81_fw_{csot,tm}.bin,
  qcom/sm8475/liuqin/{adsp,cdsp,slpi,a730_zap}.mbn, qcom/a730_sqe.fw,
  qcom/gmu_gen70000.bin, updates/ath11k/WCN6855/hw2.{0,1}/amss.bin,
  qcom/vpu/vpu20_4v.mbn, qcom/sm8450/Xiaomi-Pad-6-Pro-tplg.bin,
  regulatory.db{,.p7s}.
* pkgs/bootimg.nix: stock DTBO entries (38 files, from
  liuqin-audit/evidence/dtbo) + all 11 base DTBs of
  liuqin_images_*/images/vendor_boot.img's DTB table, vendored at
  data/stock-{dtbo-entries,base-dtbs}.tar.zst and imported with
  `builtins.path` (operator's own dump; do not publish), for the
  __symbols__ union (exactly 1744 symbols). The base set must stay
  complete: a single base DTB exports 1451 labels, which collapses the
  union to 1469 - 275 labels short of what ABL's forced stock DTBO overlay
  may reference, and ABL aborts on the first fixup it cannot resolve. The
  downstream 44/14/1781 numbers come from the larger OS2.0.6.0.VMYCNXM
  analysis tree. The boot header cmdline is
  deliberately empty (downstream native build does the same; the kernel
  reads /chosen/bootargs from the DT, ABL appends its own), and the DT
  bootargs match the downstream product default: earlycon=simplefb stays
  in the base kernelParams, while keep_bootcon is removed from the base
  string and gated behind hardware.liuqin.boot.debug (downstream
  build-bootimg.sh:40-44: it keeps simplefb0 drawing into the bootloader
  framebuffer all session, which a desktop compositor cannot draw over).
* pkgs/sensors-config.nix: vendor/etc/sensors/config (SSC registry
  inputs). Extraction: unpack the stock ROM super image, then
  vendor/etc/sensors/config; downstream build-liuqin-sensors-stack.sh
  reads it from tools/local/roms/liuqin/OS2.0.6.0.VMYCNXM/extracted/
  super-work/vendor-extract/etc/sensors. Archive it deterministically,
  `nix-store --add-fixed sha256 liuqin-ssc-config.tar.zst`, and set
  hardware.liuqin.sensors.sscConfigHash. The committed
  data/liuqin-ssc-config.tar.zst is the operator's own copy of that
  archive (register it, do not re-extract).
