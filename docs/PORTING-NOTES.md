# Porting notes: xiaomipad-6pro-mainline → liuqin-nixos

Nix expression of the downstream device work, on Linux 7.2.5 (downstream is on
6.17). A downstream behaviour is a candidate to port, not proof it is safe here.

## Real-device verification (2026-09-29)

The installed system was checked on a running tablet over the USB debug NCM
gadget (`192.168.7.2:2323`, root shell). This verifies the running NixOS
system; it does not verify the U-Boot menu or persistent `boot_b` path.

Working at the time of the check:

- DSI display/DRM, framebuffer, backlight, touch, pen, Nanosic keyboard and
  touchpad, power keys, Wi-Fi association, Bluetooth, USB shell, UFS, GPU and
  CPU capacity/energy-model support.
- The DRM connector identifies the 1800x2880 panel, but its sysfs `modes` file
  omits refresh-rate information and the panel was blank during this snapshot;
  the source-level mode list is the authoritative result below.
- PMIC GLINK battery management is active: the battery and USB power supplies
  report charging state, voltage and current. This is basic power-supply
  support; it is not proof of Xiaomi high-power charging.
- CPU idle governor is `teo`; the three capacity groups read 277/832/1024
  (rounding of the expected 278/833/1024 values).
- EAS is active (`/proc/sys/kernel/sched_energy_aware=1`); all three policies
  use `qcom-cpufreq-hw` with `schedutil`. `CONFIG_UCLAMP_TASK` is not enabled.

Not registered or not driven:

- **Audio:** `/proc/asound/cards` reports no soundcards. The four CS35L41
  amplifiers bind, but the LPASS/WCD machine driver is deferred because the
  RX/TX macro clocks and CPU DAI are unresolved.
- **Sensors:** The Android probe identified BMI3x0 accelerometer/gyroscope,
  TCS3701 ambient/CCT sensors and a TSL2522 rear ambient sensor. The SSC
  userspace path is now implemented: the package serves the registry contract,
  the persist import is atomic, and bounded `libssc` checks cover acceleration,
  angular rate, and the default SSC ambient-light Lux instance. A successful
  light check does not distinguish the front TCS3701 from the rear TSL2522.
  The stock CCT/RGB calibration records
  have no corresponding API in the pinned `libssc`, so CCT remains unimplemented
  and unverified. `/sys/bus/iio/devices` can still be empty because
  these devices are owned by SLPI rather than an AP-side IIO bus; only the
  accelerometer is bridged to `iio-sensor-proxy`. Real measurements and the
  resulting Android-derived gravity/rotation/step/tilt/motion behaviour remain
  unverified until `liuqin-sensor-check` runs against the tablet's own SLPI
  firmware.
- **PMIC ADC:** the ADC5 device has no configured channels and fails probe;
  no corresponding IIO device is present.
- **Camera capture:** only Iris codec nodes (`/dev/video0` and `/dev/video1`)
  exist; there are no media-controller or CSI/ISP capture nodes.
- **Fingerprint:** Android has an FPC1020-compatible power-button sensor and
  `fpc1552.ko`; the current system has no fingerprint device or driver.
- **Type-C high-speed path:** the UCSI power-supply child is present, but
  `/sys/bus/typec/devices` has no port and the USB gadget reports
  `current_speed=high-speed` and `maximum_speed=high-speed`. USB3, OTG role
  switching, PD/PPS negotiation and DP Alt Mode remain unverified.

Working with faults:

- Touch resume repeatedly retries firmware download and can end with
  `resume failed closed`; the input device then reappears after recovery.
- Wi-Fi is usable but ath11k reports repeated `msdu_done` errors and has
  experienced carrier reconnects.
- Battery charging currently reports `charge_type=Fast`, but the live Xiaomi
  attributes read `raw_xm_authentic=0`, `raw_xm_pd_verified=0`,
  `raw_xm_fastchg_mode=0` and `raw_xm_power_max=0`. The connected USB source is
  limited to 5 V/0.5 A, so PD/PPS/MiPPS high-power charging is not validated.
- The eUSB2 repeater and GPU log occasional recoverable errors.

The Android probe reported 35 sensor-service entries, 43 ALSA PCM endpoints,
three physical camera sensors (six HAL devices), and a power-button fingerprint
sensor. Those counts describe the vendor stack, not features currently
available in this system. Hall switches are already covered by `gpio-keys`.
Android itself did not expose a magnetometer, barometer, proximity sensor,
GNSS, NFC or vibrator feature; those should remain marked as unconfirmed or
disabled rather than counted as missing Android hardware.

Thermal support is partial: the current system has 38 zones covering the
battery, TSENS CPU/GPU, video, memory, camera, CDSP and PMIC paths. The Android
snapshot had 81 zones, including vendor `charger`, `wifi`, `xo`, `ddr`, `flash`
and connector zones that are not present under those names here.

## USB-C / USB3 / DP / fast charging: what the static analysis settled (2026-09-29)

Analysis that needs no device (vendor 5.10 sources, the stock firmware and
deployed binaries, upstream 7.2.5) pins this chain down. The full reports are
in `../../liuqin-stock-dump/re/usb/` (`batterysecret.md`, `dp-altmode.md`,
`phy-table.md`, `dt-config.md`, `mipps-spec.md`, `phy-table.patch`; not in
git), and the implementation checklist is the "已确定的逻辑" section of
`docs/TODO/USB-C-USB3-FASTCHARGE.md`. In short:

- **PD/PPS is the ADSP's job.** The deployed kernel and modules carry no
  AP-side PD stack: the AP can only write `input_current_limit`, and the
  charging tier is derived from `usb_type` + `pd_verified` + `power_max`
  (`qti_battery_charger.c:1497`). Standard PD/PPS therefore needs no port,
  only not being interrupted.
- **MiPPS (67 W) is driven by `/vendor/bin/batterysecret`, not by the kernel.**
  HMAC-SHA-256 with keys in `.data` (`0x7490..`; hw_id 17, i.e. liuqin,
  selects `0x7510`), talking to the UVDM sequence through
  `/sys/class/qcom-battery/{verify_process,verify_digest,request_vdm_cmd,…}`.
  0006 exposes the kernel side of that transport, but not yet the ABI a daemon
  needs: seven changes remain (see the TODO document), and the userspace
  daemon after them. `is_old_hw` does not exist in the deployed kernel;
  `BATTERY_DIGEST_LEN=32`.
- **liuqin has no USB3 redriver.** Board-id `0x10008` / miboard-id `0x10` apply
  overlay-15 only; `onnn,redriver` belongs to waipio-QRD's overlay-25/26/27.
- **The combo PHY is a V6 layout.** The stock `qcom,qmp-phy-init-seq` (174
  entries) matches the upstream SM8550/V6 table (TX, PCS and PCS_USB
  bit-identical; COM has the same 48 offsets but 24 different values), while
  7.2.5 selects the sm8350 table for `qcom,sm8450-qmp-usb3-dp-phy`; upstream
  parses no DT init-seq at all.
- **DP Alt Mode reuses the upstream protocol.** `pmic_glink_altmode.c` and the
  vendor `altmode-glink.c` agree field for field, so DP bring-up is DT
  (`pmic-glink`'s `connector@0` with graph endpoints, `usb_1_qmpphy`,
  `mdss_dp0`, FSA4480) plus configuration.
- **Type-C role/orientation.** The `connector@0` graph also provides UCSI's
  role switch; `orientation-gpios` is the mechanism, but GPIO91 is only a
  candidate here (the vendor uses it as a portselect pinctrl and the evidence
  is not sufficient), so the plan deliberately leaves it out of the DTS. The
  vendor counterpart is `usb-role-switch` + EUD extcon.

Implementation-level artifacts (not in git; they embed vendor-private material)
live under `liuqin-stock-dump/re/usb/`:

- `dt-config.md`: pasteable DT fragments plus config lines, the electrical
  facts still open, and a first-boot checklist;
- `phy-table.patch`: draft adding the `sm8450_usb3dpphy_cfg` combo-PHY table
  (V6 base plus the board delta); applies cleanly to 7.2.5;
- `mipps-spec.md`: MiPPS daemon ABI, state machine, digest byte order and key
  selection, plus the seven minimal 0006 changes.

## Kernel

Sixteen patches, applied in filename order (there is no 0014: it was a
temporary PCIe PHY diagnostic):

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
| 0013 | the board's own QMP PCIe PHY cape tables (21 values); without them the PHY times out and the WCN6855 never enumerates |
| 0015 | temporary workaround: up to five delayed display-pipeline stop/start cycles after U-Boot hands over a still-running panel |
| 0016 | CPU capacity and energy model for the three Kryo clusters (see below) |
| 0017 | CPU thermal cooling maps: the zones' passive trips drive their cluster's cpufreq cooling device (see Energy) |

Three config inputs:

- `kernel/config.nix` — structured answers, installed system. `enableCommonConfig`
  is deliberately **off** (`kernel/default.nix`): the base is the arm64 defconfig
  plus these answers. Of nixpkgs common-config's ~470 `=y/=m` answers only ~180
  hold here (BINFMT_MISC, USERFAULTFD, KPROBES/FUNCTION_TRACER, ANDROID_BINDER_IPC,
  FS_VERITY/FS_ENCRYPTION … are out), and `config.nix` was deduplicated against
  common-config while it was still enabled, so re-enabling means re-deriving that
  diff;
- `kernel/liuqin-firstboot.config` — raw fragment appended in `postConfigure`
  for symbols a structured answer cannot settle (Kconfig question order, or
  `olddefconfig` downgrading `=y` to `=m`), then `make olddefconfig`;
- `kernel/installer.config` — same mechanism, installer kernel only (its RAM
  image has no module tree, so the USB/HID gadget paths are built in).

Both fragments are appended **before** a single check pass, and the expectations
are derived from the fragments themselves (each `CONFIG_X=y` must survive as
`=y`, each `CONFIG_X=m` as `=y|=m`; `ZRAM` is an explicit exact-`m` exception —
zram-generator modprobes it with `num_devices=1`). The hand-written symbol lists
this replaced had missed four lines that could never hold: `NFT_COUNTER` does
not exist, `NFT_FIB` has no prompt (the family helpers select it), `NFT_FIB_INET`
depended on helpers nobody enabled, and `NFT_REDIRECT` is really `NFT_REDIR`.

Nothing in this derivation is an ImportFromDerivation: `buildLinux` hands
`build.nix` an explicit `config`, so the generated `.config` is an ordinary
build input (the `allowImportFromDerivation` knob only matters for
`linuxManualConfig` / `linuxPackages_custom`).

The experimental DRAM-resident console patch was removed: unreliable on this
device.

## CPU scheduling: cluster capacity and the Energy Model

The three Kryo clusters are three different cores at three different maximum
frequencies (4×A510 at 2.016 GHz, 3×A710 at 2.7456 GHz, 1×X2 at 3.1872 GHz -
the frequencies `qcom-cpufreq-hw` reads out of the EPSS LUT), and no upstream
device tree says so.  With no `capacity-dmips-mhz` on any CPU,
`topology_parse_cpu_capacity()` leaves `raw_capacity` NULL,
`topology_normalize_cpu_scale()` returns before writing a scale and every CPU
keeps the default `cpu_capacity` 1024.  `SD_ASYM_CPUCAPACITY` is then never set
(no misfit handling, no capacity-aware placement), and
`cpufreq_register_em_with_opp()` fails for the same reason a second time: it
requires `dynamic-power-coefficient`.  Without both, EAS is unreachable - the
kernel could not tell the A510s and the X2 apart at all.

`patches/kernel/0016` puts both properties on the board's CPU nodes with the
values the stock bootloader hands the vendor kernel
(`liuqin-audit/evidence/final-runtime.dts`, the `qcom,kryo` nodes): DMIPS/MHz
1024 / 2253 / 2386 and capacitance 100 / 257 / 509.  The rating is per MHz and
`arch_topology` scales it by each policy's `cpuinfo.max_freq`, giving expected
capacities of 278 / 833 / 1024; this kernel's sysfs values read 277 / 832 / 1024
after integer rounding.  The coefficients are what makes the EM work:
the driver adds every LUT OPP with its own voltage (0.864 V at 2.016 GHz, for
example), and `dev_pm_opp_calc_power()` then has everything for
`P = C·V²·f`.  Measured before the change on the unit (2026-09-28):
`cpu_capacity` was 1024 on all eight CPUs and `/sys/kernel/debug/energy_model`
was empty.

Re-check on a running system:

```sh
cat /sys/devices/system/cpu/cpu[0-7]/cpu_capacity  # 277 277 277 277 832 832 832 1024
ls /sys/kernel/debug/energy_model/                 # perf domains 0-3, 4-6 and 7
cat /proc/sys/kernel/sched_energy_aware            # 1
```
`cpu_capacity` is read-only; the only way to set it is the device tree.  The
DTB is also what `overlay.nix`'s `liuqinKernelDtb` guards: it decompiles the
built board DTB and fails the build if the six property/value pairs are not
there, because losing them again would be silent.

## Energy

Wired here, beyond the CPU scheduling above:

- `cpuidle.governor=teo` (`modules/liuqin/default.nix`).  The firstboot
  fragment builds TEO in and selects it for the installed system.  The running
  tablet reports `teo` in
  `/sys/devices/system/cpu/cpuidle/current_governor`.
- `networking.networkmanager.wifi.powersave` stated explicitly, and `iw`
  installed so the state can be read back (`iw dev wlp1s0 get power_save`):
  mac80211's debugfs is not built in this kernel, and nothing else in the
  closure can show it.
- CPU thermal cooling maps (`patches/kernel/0017`).  Upstream SM8450 declares
  passive trips on every CPU zone and `#cooling-cells` on every CPU, but no
  cooling map: the per-policy `cpufreq-cpuN` cooling devices were bound to
  nothing, so the OS could not throttle at all and only the hardware LMh
  limiter reacted.  The maps point each zone's trips at its cluster's policy
  device, trips untouched (nothing throttles below 90 °C).

Not done, in rough order of expected value:

- **Panel refresh rate.**  The mainline driver exposes one fixed 120 Hz mode:
  `pipa_mode_120` is the only mode returned by `nt36532_get_modes()`.  The
  Android audit and final runtime DT show the active M81PB panel supports
  **144, 120, 90, 60, 50, 48 and 30 Hz**, including a `wqhd_60hz_index_00`
  timing.  Adding 60 Hz first is useful for battery life; each mode needs its
  panel timing-switch command, DSI clock/DSC validation and real-device test.
  The display is the largest consumer on a tablet, so dynamic refresh support
  remains the biggest single power item.
- **IPA (`power_allocator`) for the CPU zones** - what the energy model from
  patch 0016 is for.  Deferred because `sustainable-power` needs tuning and
  the current PMIC GLINK readout is a charger/battery estimate rather than a
  calibrated board input measurement.  A USB power meter is still needed to
  choose a defensible `sustainable-power` value.
- **CPU to DDR bandwidth.**  Interconnect providers are registered, but the CPU
  nodes have no `interconnects` and there is no CPU bwmon/memlat device
  (`/sys/class/devfreq` carries only the GPU and UFS). CPU frequency therefore
  has no policy-level memory-bandwidth vote. `sm8550` has `cpu_bwmon`; porting
  the equivalent path is a separate workload-performance project. It affects
  memory-bound load scaling, not the basic idle governor or EAS enablement.
- **uclamp**: `# CONFIG_UCLAMP_TASK is not set`.  Enabling it is free but
  does nothing until something sets per-task hints, so it waits for that
  policy rather than for the config.
- **GPU devfreq policy.** The running mainline system uses
  `simple_ondemand` (220--818 MHz). The Android audit records vendor KGSL
  frequency tables and limits, but does not establish a portable `msm/tz`
  governor contract. Treat this as a separate sustained-GPU power/performance
  investigation, not as a CPU scheduler failure.
- **PCIe ASPM**: this port cannot even read the link state (`lspci` shows no
  LnkCtl for the WLAN bridge), and ASPM has a history of ath11k link
  problems, so it stays at the kernel default.

Checked and already fine: interrupt affinity (nothing lands on the single X2;
ath11k's MSI vectors sit on cpu1..cpu6, ufshcd on cpu0), the GPU and UFS
devfreq governors (`simple_ondemand`, 220 MHz and 75 MHz floors), and the
per-CPU idle states (both `cpu-sleep-*` states are in use).

## Command line

Installed system (extlinux `APPEND`; `init=` and `root=fstab` are added by the
loader integration):

```text
qcom_q6v5_pas.slpi_auto_boot=0 rootwait initcall_blacklist=simplefb_driver_init
earlycon=simplefb console=tty0 firmware_class.path=/var/lib/firmware
root=fstab loglevel=7 lsm=landlock,yama,bpf
```

`earlycon=simplefb` plus `console=tty0` keep a console alive from the first line
and hand it to the panel; the loglevel stays at 7 (NixOS' `loglevel=4` hid the
log). `keep_bootcon` is deliberately **not** in the default: it keeps simplefb0
writing into the bootloader framebuffer all session, which a compositor cannot
draw over — it lives behind `hardware.liuqin.boot.debug` (the RAM installer does
carry it). The SMMU/display-clock blacklist and the option that enabled it
(`hardware.liuqin.boot.legacySmmuDispccBlacklist`) are gone: a configuration
with those initcalls disabled crashes this unit.

`firmware_class.path=` takes **exactly one directory** — `fw_path_para` is a
single `char[256]` (`module_param_string`, `drivers/base/firmware_loader/main.c`)
and there is no `:` splitting. A `a:b` value invalidates the whole parameter and
every `request_firmware()` after that fails with `-2`; that is how the RAM
installer's WLAN was dead until 2026-09-28. Both call
sites now point it at `/var/lib/firmware` only, which the initrd seeds with the
full (installed) or WLAN-only (installer) tree; the loader also tries the
`.zst`-compressed variants (`FW_LOADER_COMPRESS_ZSTD=y`).

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
- The panel hardware's Android/vendor timing set is 144/120/90/60/50/48/30 Hz;
  the current mainline panel implementation advertises only 120 Hz.
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

Not done, in rough order of expected value:

- **Kernel-side display-pipeline stop at probe**, so that U-Boot boots light
  the panel at the first modeset without the repeated visible dark seconds
  patch 0015's five-attempt retry loop can cost.

  The hand-off difference behind the loop is known; the exact hardware state
  that makes the first modeset fail is still unknown. Booted through ABL with
  a DT that does not name `/reserved-memory/splash_region` (every current flake
  boot image; patch 0001 renames the node to `linux_splash@b8000000` on
  purpose) the kernel inherits a
  **stopped** display: ABL looks that path up in the DT it is about to jump to
  (`QcomModulePkg/Library/BootLib/UpdateDeviceTree.c`, `UpdateSplashMemInfo`)
  and, when the lookup fails, calls `DisableDisplay()` -- display power off,
  display clocks off, TE/RST pin reset.  Measured 2026-09-28: first modeset at
  ~1.9 s, lit, no cycle.  Booted through U-Boot the kernel
  inherits a **running** pipeline instead: ABL has to keep the display up for
  U-Boot's menu, and `sysboot` hands the kernel over with ABL out of the loop.
  The first in-place modeset then leaves the panel dark and patch 0015 cycles it
  from a timer.

  **Hypothesis, not yet confirmed:** U-Boot leaves the ABL-configured DPU
  video timing and bonded DSI pipeline running, while the kernel's DRM objects
  begin with software state that treats them as disabled. Its first enable may
  therefore reprogram active hardware without first stopping the old timing
  engine and waiting for the disable to latch. The upstream
  `dpu_encoder_phys_vid_disable()` path returns early when its software state
  is already disabled; when it does stop an active encoder, its comment says
  that re-enabling before the disable reaches vblank can prevent new settings
  from latching. This fits the ABL/U-Boot comparison, but does not identify
  whether the decisive state is in DPU/CTL, either DSI host/PHY, or the panel
  reset sequence. The later success of patch 0015's cycles does not isolate
  that state either.

  To test the hypothesis, capture DPU interface/timing and both DSI host
  status registers immediately before the first modeset on each boot path.
  Then try an ordered quiesce before the first modeset: stop DPU video timing,
  wait for idle/vblank, stop both DSI streams, and let the normal panel reset
  and prepare sequence run. Add a rail power cycle only if that narrower
  teardown fails. Keep the U-Boot menu visible until the quiesce begins.

  The candidate kernel fix belongs before its first modeset (`msm` probe /
  `dpu_kms_hw_init()`, or the panel driver's first `prepare`), as late as
  possible so earlycon can keep using the inherited framebuffer. First
  quiesce the CTL/timing engine and both DSI video streams, then let the
  panel driver's normal `reset-gpios` pulse and `prepare` sequence run. The
  exact shutdown order and any required vblank/idle wait need on-device
  testing. If that is insufficient, test ABL's fuller power/clock teardown.
  Patch 0001 currently marks the display rails `regulator-always-on` because
  the bootloader splash scans out until takeover; a rail power cycle would
  require revisiting that policy and protecting the earlycon window.
  Register-level references: the vendor tree in `Xiaomi_Kernel_OpenSource/`
  (DPU/DSI drivers) and the runtime DT in `liuqin-audit/evidence/`.

  Acceptance: with the DT **not** renamed for this path (`splash_region@
  b8000000`, so ABL keeps the display for the menu) and patch 0015 disabled
  (`liuqin_panel_cycle_attempts = 0`), a boot through the U-Boot menu must light
  the panel at the first modeset and leave it lit.  Test through the normal
  path (U-Boot menu, `sysboot`/extlinux): an ABL `fastboot boot` would take the
  clean path itself and hide the problem.

  Related: patch 0014 (a panel-side "be quiet before prepare", only the panel
  command, no power/clocks) failed on the unit; patch 0015's comment records the
  early/late asymmetry (cycles before ~8 s did not take, later ones did).  Once
  this lands, 0015 can be deleted and `liuqin-screen-refresh` stays retired.

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
  `firmware_class.path` and avoiding the read-only `/lib` symlink. That
  parameter takes **exactly one** directory (no `:` splitting — see
  "Command line"), so it must not be extended with a second path.

Five defects fixed to get here, each verified on the unit:

| defect | fix |
|---|---|
| `CONFIG_SQUASHFS_CHOICE_DECOMP_BY_MOUNT` unset, so mount's `loop,threads=multi` answered `EINVAL` and `/sysroot/nix/.ro-store` never mounted | set in `kernel/installer.config`, asserted |
| stage 1's `init=` lookup resolved inside `/sysroot`, and ABL appends its own `init=/init` last | `ExecStartPre` plants the marker, listed in `boot.initrd.systemd.storePaths` |
| the filtered live toplevel dropped `boot.json`, which stage 1 needs for the etc image and `env`/`modprobe` | keep `boot.json`, with `kernel`/`initrd` repointed |
| `CONFIG_EROFS_FS` unset, so the `/etc` EROFS image failed and the initrd stopped in emergency mode | enabled in `kernel/liuqin-firstboot.config`, asserted in both check loops |
| `firmware_class.path` was a `a:b` pair, which the kernel reads as one invalid path, so every runtime `request_firmware()` failed `-2` and the installer's WLAN never came up (`amss.bin` `-2` → MHI `-110`) | point it at `/var/lib/firmware` only |

Measured: gadget up at ~10 s, telnet answering during the initrd, sshd and the
telnet shell at ~30 s after switch_root, `systemctl is-system-running` =
`running` with no failed units, `/etc` on the EROFS overlay, three USB units
active, and WLAN up (`wcn6855 hw2.1` → `wlp1s0`) from the initrd firmware
subset.

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

The union is applied as one `/plugin/` overlay that carries the sink node plus a
`__symbols__` entry per label, and `fdtoverlay` merges it in (properties are
replaced one by one) — pure dtc/fdtoverlay, no text surgery on dtc's output. The
build then decompiles the result and asserts every union symbol is present and
pointing at the sink (the previous awk-based splice was
replaced, and the check was strengthened from "present" to "redirected").

The checked-in stock archive holds 38 DTBO entries and 11 base DTBs, and the
build asserts a 1744-symbol union. The downstream analysis tree uses 44/14 and
1781 symbols from another OS build; those counts are not correctness conditions
for this archive. The kernel's own DTB additionally carries ~395 `__symbols__`
labels of its own (they are not part of the stock sets and therefore not
referenced by any stock overlay); they are left pointing at their real nodes.

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
tree. That subset is what makes the installer's WLAN work: both call sites set
`firmware_class.path` to exactly `/var/lib/firmware` (one directory — see
"Command line") and the loader picks the `.zst`-compressed blobs up there,
exactly like the installed system does (verified on the unit). Nothing proprietary is committed: the release is fetched by hash and
the operator inputs are `requireFile`. Two archives stay in the tree because the
release does not carry them (`data/stock-base-dtbs.nix`,
`data/stock-dtbo-entries.nix`; it ships no `vendor_boot.img`).

The SSC archive used by the first NixOS revision contained the per-device
`config/` registry but not the `sns_reg.conf`/`sns_reg_version` files that
`hexagonrpcd` looks up at runtime. The running device logs both paths as
missing before the SLPI crash. `pkgs/sensors-config.nix` now installs those
paths, accepts the sibling files when present, and synthesizes the audited
plain-text contract for older config-only archives. The private per-device
registry is still provisioned from persist and is never copied into the Nix
store.

## Not enabled by default

- TM/CSOT automatic selection for other panel batches;
- WCD938x/SoundWire microphone capture. The four-speaker TDM graph is present
  in the DTS, but the real device currently registers no ALSA card because the
  LPASS/WCD probe is deferred; the downstream 6.17 DTS also describes the
  capture graph;
- CSI/ISP camera capture (the current Iris support only exposes codec nodes);
- FPC1020-compatible power-button fingerprint reader;
- AP-side BMI3x0/TCS3701/TSL2522 direct IIO drivers (the SLPI/SSC path is the
  implemented contract); gyro/light application acceptance, CCT/RGB, and
  desktop consumers remain unverified;
- USB3/OTG role switching and DP Alt Mode: the vendor/upstream logic is now
  determined (static analysis section above and
  `docs/TODO/USB-C-USB3-FASTCHARGE.md`); the DT/config changes are not
  implemented yet, so both DTS overlays still select the validated USB2
  peripheral role;
- Xiaomi MiPPS/PPS userspace authentication: the protocol, digest layouts and
  keys are recovered from `/vendor/bin/batterysecret` (report under
  `liuqin-stock-dump/re/usb/`); the daemon is not implemented, and `0006` still
  only exposes the kernel transport and raw attributes;
- the touchscreen firmware payload in the installer;
- re-enabling the duplicate ramoops region.

Each item needs its own kernel profile or device test, not an installer change.

## Known refactors (TODO)

- `config/installer.nix`: `usbGadgetSetup` / `usbShellLogin` / `screenRefresh`
  are **done** — they now live in `pkgs/usb-gadget.nix`, `pkgs/usb-login.nix`
  and `pkgs/screen-refresh.nix` (the last shared with the installed system's
  `liuqin-screen-refresh.service`). The install path itself is no longer in
  this file: upstream `nixos-install` runs against the operator's mounted
  target.
- `modules/liuqin/hardware.nix`: **done** — the shell the units ran inline now
  lives in `pkgs/` (backlight default, persist provisioning, WLAN/BT identity,
  SLPI lifecycle, screen refresh, sensor-check, sensor-proxy re-announce) and
  the module only wires units; the device-unique paths travel as arguments, so
  each command stays runnable by hand.
- `modules/liuqin/initrd-guard.nix`: still open — the guard script needs the
  same `pkgs/` + `writeShellApplication` treatment.
