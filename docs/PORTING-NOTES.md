# Porting notes: Xiaomi Pad 6 Pro (liuqin, SM8475) on Linux 7.2.5

NixOS support for the Xiaomi Pad 6 Pro (`xiaomi,liuqin`, SM8475) on Linux
7.2.5, built from the kernel.org tarball plus the device patch series in
`pkgs/kernel/patches/`.  This is the *current state* record: subsystem status,
the MiPPS key contract, debug/deployment methods, and how the kernel patch
series is organised.  Dated bring-up history, failed experiments and
per-run measurements live in git history.

Verification labels used throughout:

- **verified** — observed on the tablet.  The date is the last run recorded
  in the sources.
- **unverified** — implemented or expected, never confirmed on hardware.
- **not implemented** — no code path exists.

Companion documents: `README.md` (build outputs and configuration model),
`docs/INSTALL.md` (install/update/recover), `docs/BOOT-ARCHITECTURE.md`
(boot chain and U-Boot menu), `docs/TODO/CAMERA-MAINLINE.md` (camera detail),
`docs/TODO/LID-SUSPEND-LOOP.md` (cover-close suspend loop).

## 1. What works and what does not

### Summary

| Subsystem | Status | One-line limit |
| --- | --- | --- |
| DSI display / DRM / backlight | verified | one fixed 120 Hz mode; the U-Boot path needed an early pipeline stop/start to keep the picture, now in patch 0003 |
| Touch, pen, keyboard folio, touchpad, keys | verified | touch drifts when an external DP monitor is bound (Mutter heuristic); touch resume retries firmware |
| Camera (3 sensors + AF) | verified | one sensor at a time; app recording/JPEG paths broken; see `docs/TODO/CAMERA-MAINLINE.md` |
| Audio playback (CS35L41) | verified | four speakers play; the USB-C/FSA4480 headset route is not ported |
| USB3 device (peripheral) | verified | 10-hotplug stability record still open; the cover-close suspend loop re-enumerates the gadget, see `docs/TODO/LID-SUSPEND-LOOP.md` |
| Type-C host + OTG power | verified | 10-hotplug record and automatic gadget re-bind still open |
| DP Alt Mode | verified | single-link-rate tables (HBR2 capture); 2-lane DT only; repeated hotplug unverified |
| Standard PD / PPS | ADSP-owned | no AP-side control; measured working, not formally accepted |
| Xiaomi MiPPS (67 W) | verified | keys are operator-supplied; `reverseAuth` (cmd 8) unverified |
| Sensors (SSC/SLPI) | partly verified | accelerometer + ambient light live on the SensorProxy D-Bus API (four orientations and all five tilt states measured 2026-10-07); gyroscope has no userspace consumer; CCT/RGB, light-sensor identity, fusion and suspend/resume unverified |
| Wi-Fi / Bluetooth | verified | ath11k `msdu_done` noise, reconnects; 5 GHz fixed 2026-10-07 by booting the vendor fw/BDF set (-48 dBm ch161, 0 % loss) |
| Storage (UFS, root guard) | verified | root ext4 bitmap-checksum errors in dmesg (TODO) |
| CPU scheduling / Energy Model | verified | — |
| Thermal | partial | 38 zones vs 81 on Android; no IPA |
| Fingerprint (FPC1264) | verified | one finger per account; enrolment needs a password login (or the polkit prompt) to authorise it; press firmly |
| Microphone capture (WCD9385) | verified | AMIC1 -> ADC1 -> TX macro -> `TX_CODEC_DMA_TX_3`; the vendor has no AP-visible DMIC |
| U-Boot SuperSpeed | not implemented | U-Boot is USB2 fastboot |

### Display

- DSI panel `xiaomi,pipa-nt36532` (CSOT module `m81_42_02_0b`), 1800x2880,
  `MIPI_DSI_MODE_VIDEO`, two DSI hosts, KTZ8866 backlight.  The DTS delay
  firmware fallback `novatek/liuqin/novatek_nt36532_m81_fw_csot.bin` is the
  correct one for this unit; automatic TM/CSOT selection is **not
  implemented**.
- DRM client is `DRM_CLIENT_DEFAULT_FBDEV`, giving `fb0`/`msmdrmfb` and a
  getty on `tty1`; `earlycon=simplefb console=tty0` keeps the console alive
  from the first line.  `fb0: framebuffer is not in virtual address space`
  is informational.
- **verified** (2026-09-29): panel lights, backlight, console, fbcon on the
  DSI panel.
- **Limit — one refresh rate.** The mainline panel driver exposes only the
  120 Hz mode.  The panel hardware supports 144/120/90/60/50/48/30 Hz
  (Android/vendor timing set).  Adding 60 Hz is the single most valuable
  power item; each mode needs its panel timing-switch command, DSI/DSC
  validation and a device test.
- **U-Boot first modeset: fixed 2026-10-07, verified on the unit.**  The panel
  used to lose the picture right after the first modeset: the early console
  *is* on the glass (a photo shows it - timestamps 0.000000, last line at
  0.026 s - written into ABL's framebuffer at 0xb8000000, which can only be
  visible while ABL's DPU and DSI are still scanning it out), then the screen
  goes white (a powered panel with no valid stream) and black.  Register
  snapshots (a full DSI/DPU dump from `/sys/kernel/debug/dri/0/kms`, 81
  blocks, 0.5 s granularity) show the engine "enabled" throughout, so no dump
  can see the fault.  The bootloader hands over a *live* pipeline, and
  mainline's in-place take-over does not produce a picture on this board: what
  is needed is a real stop of the whole pipeline (DPU timing/CTL/DSC, both DSI
  hosts, the PHYs, the panel) and then a clean start.  Patch 0003 now does
  that stop *before* programming in two places it can (`msm_dsi_host_power_on()`
  stops the controller first, since `dsi_sw_reset()` preserves the enable bits
  it finds; `dsi_phy_7nm.c` no longer saves/replays the bootloader's PLL
  dividers over the driver's own configuration), and - because those two are
  not sufficient on their own (measured) - the kernel also performs **one**
  DPMS off/on 1.5 s after the fbdev client's first modeset, while the fbdev
  client still owns the display.  Verified with the user watching: the panel
  lights at ~4.4 s (`liuqin: stopping/starting the pipeline to light the first
  modeset` at 3.36 s) and stays lit.  That early timing is load-bearing: the
  old five-shot cycle at 6/10/14/18/22 s ran after GDM had taken DRM master,
  where `fb_blank()` is refused and `drm_fb_helper_blank()` drops the error -
  its blanks were never undone, which is why the screen used to light "very
  late", and sometimes not at all.
  The same measurement retired three earlier theories, each with evidence: a
  panel power-on reset (sleep-in + supply cycle + DPU control-path reset
  changed nothing), the `clk_ignore_unused pd_ignore_unused` late-init gating
  ("clk: Not disabling unused clocks" printed and the panel still died), and
  the backlight (ktz8866 defaults to 1500/2047, on from probe).  Follow-up:
  do that stop inside the driver before the first programming (instead of as a
  second DPMS commit), which should light the panel at ~2 s with no visible
  cycle; `liuqin-screen-refresh` is gone from the installed system for good -
  its late blank/unblank could only darken a working panel.
- **Do not** re-add the `arm_smmu_init` / `disp_cc_sm8450_driver_init`
  blacklist: it crashes this unit, and the option that enabled it was
  removed.

Hand-off contract, read from the sources and then measured.  ABL's half is
`QcomModulePkg/Library/BootLib/UpdateDeviceTree.c` in Qualcomm's public ABL
source (the `LA.VENDOR.1.0.r2-09400-WAIPIO.QSSI14.0` tag matches this
generation) — `UpdateSplashMemInfo()` looks `/reserved-memory/splash_region` up
in the DTB of the image it is about to jump to and, when the node is missing,
calls `DisableDisplay()`: display power off, display clocks off, TE/RST reset.
With the node present ABL instead leaves the display alive, which is what the
U-Boot image relies on for its menu; what reaches Linux is that *powered* state
with the link already idle (measured 2026-10-07, above), not a live pipeline.
Android's kernel does the opposite of a cold start and *adopts* ABL's running
pipeline (`techpack/display/msm/dsi/dsi_display.c`:
`dsi_display_cont_splash_config()` sets `is_cont_splash_enabled`, and
`dsi_display_enable()` then returns early with "cont splash enabled, display
enable not required"; ABL even hands the DSI PLL calibration codes over through
`/soc/dsi_pll_codes`).  Mainline drm/msm has no such path, and the other
mainline ports that boot from this bootloader keep the node anyway (Nothing
milos, `sm8450-samsung-r0q`, `sm8550-samsung-q5q`, `sm8650-ayaneo-pocket-s2`),
so on mainline the first modeset always programs the display from scratch.  The
measurements above show that doing so needs no power cycle and no workaround:
what ABL leaves behind here (the panel's rails up, an idle DSI link, a stopped
DPU) is harmless, and the only thing that ever kept this panel dark was the
port's own blank/unblank workarounds.

### Touch and input

- Novatek NT36523 SPI touchscreen, pen, Nanosic WN8030 keyboard-folio
  bridge (keyboard, media keys, touchpad) and the power keys are **verified**
  (2026-09-29).  Hall switches are covered by `gpio-keys`.
- Touch resume repeatedly retries the firmware download and can end in
  `resume failed closed`; the input device reappears after recovery.  The
  installer does not ship the touchscreen firmware payload (its panel is
  output-only); the installed system carries it.
- **Touch drift with an external DP monitor.** With a DP display attached,
  touch coordinates drift.  Root cause is Mutter's touchscreen-to-output
  association: the I2C touchscreen reports vendor/product `0x0000` and no
  resolution, and the DSI output is `unknown/unknown/unknown`, so the
  same-vendor/product and same-size heuristics cannot bind it.  Two
  attempts failed and must not be repeated blindly: (1) the relocatable
  GSettings touchscreen output override matches no monitorspec and makes
  touch unresponsive; (2) adding `input_abs_set_res()` in the driver made
  evdev report **zero** events (cause unknown; the change was reverted).
  Remaining options: a synthetic EDID on the DSI connector (vendor/product),
  or an explicit Mutter/GNOME mapping; `modules/liuqin/firmware.nix` carries
  the same record next to the driver code.
- The touchscreen firmware parser should validate ranges
  (`offset <= length && size <= length - offset`) before checksums/copies;
  the 7.2.5 adaptation does not do this yet.

### Camera

All three modules capture on mainline through CAMSS plus libcamera's `simple`
pipeline with the software ISP, and the GNOME path (portal → pipewire →
libcamera) works.  Contrast autofocus is a simple-IPA algorithm ported from
the RPi IPA's `Af` (CDAF path), driven by a focus figure of merit that the
software ISP measures on the processed frame (both the CPU and the EGL
debayer paths); the pipeline handler only applies lens moves, and the AGC and
AWB freeze while a scan runs.  Kernel side is patch 0012/0013; userspace is
`pkgs/libcamera-af/`.  **Device-verified 2026-10-07: the IPA-side autofocus
and the lens channel work, and a scan costs ~5 s at the platform's 10 fps
(the earlier pipeline-side implementation took ~27 s); the dioptre-to-DAC map
is provisional until the module's V-curve is measured.  The software ISP uses
libcamera's default EGL debayer, which rescales the sensor's full frame to
the stream size and so keeps the field of view (the CPU debayer has no
scaler and centre-crops); the EGL focus figure of merit tracks focus well
enough for the AF (2026-10-07).**

Operating facts (full detail in `docs/TODO/CAMERA-MAINLINE.md`):

- rear S5KJN1 (wide, csiphy3, 4080x3060, 4 lanes, 700 MHz menu rate, mounted
  180°, I2C 0x10, VFLIP default 1); front IMX596 (csiphy2, 2592x1952,
  678.4 MHz measured, 4 lanes, streams with `0x0100 = 0x0103`); depth
  SC202CS (csiphy1, 1600x1200 mono, 1 lane, 360 MHz, I2C 0x36).
- The modules share `csid0 -> vfe0_rdi0`, so exactly one camera can be
  routed at a time.  **Never route at boot**; a leftover enabled
  phy→csid link makes the CSID resolve two inputs and nothing streams.
  Reset with `media-ctl -r -d /dev/media0`.
- The sensor module is blacklisted from udev autoload and loaded late by the
  `liuqin-camera-probe` oneshot (three attempts, 5 s apart).  A failed probe
  leaves every camera absent; touching the stack in that state can wedge the
  SoC — reboot.
- libcamera routes the graph itself: `cam --stream role=raw --capture=N`
  (the `cam` on `PATH` is stock libcamera; `cam-af` runs the patched build).
  Focus is a stream-time action:
  `v4l2-ctl -d <dw9768-subdev> --set-ctrl focus_absolute=536`.
- Only one consumer can hold the camera; wireplumber's v4l2 monitor counts
  as one.  In a GNOME session mask it for a raw capture.
- Open items: SC202CS gain semantics, depth flip register, AF quality
  limits, app photo/recording paths, suspend/resume
  re-capture, colour calibration, UVC gadget, and the always-on bring-up
  workaround (patch 0013) that still needs a minimal-set bisect.

### Audio

The card is `XiaomiPad6Pro` (`sm8450-sndcard`); the DSP topology exposes
`MultiMedia1 Playback` (pcm 0) and `MultiMedia2 Capture` (pcm 1), and the
DAI links below them are internal DPCM backends.  Patch 0004 carries the
AudioReach/`sc8280xp` path with the CS35L41 amplifiers and `wm_adsp`; patch
0015 adds the WCD9385 RX/TX SoundWire capture graph (2.75 V micbias, guarded
UCM `Mic` device); patch 0016 names the four amplifiers so the driver selects
this board's Halo payloads.

- **Loudspeaker playback: verified** (2026-10-06).  `aplay -D plughw:0,0`
  and `pw-play` both run to completion and the four speakers are audible.
  The stall seen before was the tertiary-TDM backend graph never being
  started: the ported `q6tdm_ops` DAI table had no `.trigger`, so
  `GRAPH_START` was never sent for it and the DSP never consumed the write
  endpoint (`pcm0p/sub0/status` stuck in SETUP).  Patch 0004 carries the fix.
- **WCD9385 analog capture: verified** (2026-10-06).  `arecord -D hw:0,1`
  records live signal on ch0; ch1 is silent by design (only DEC0/ADC1 is
  routed).  Two channels, 48 kHz.
- **Not implemented:** the USB-C/FSA4480 headset path (the WCD playback link
  is wired but inert), the VA/digital microphones (the vendor DT disables
  every `swr-dmic` slave and no DMIC pinctrl exists), WSA883x backends, and
  the rest of the vendor PCM endpoints.
- The amplifiers load the vendor's Halo payloads
  (`cirrus/cs35l41-dsp1-spk-prot-10251826.*`, extracted from the stock vendor
  partition and registered as a `requireFile` payload), and
  `pkgs/firmware-path.nix` mounts an overlay of the vendor payloads, the
  system firmware tree and the per-device calibration records under
  `/var/lib/firmware` and points the loader at it - without the calibration
  the CS35L41 protection gate stays closed.  The overlay reads its lower
  layers once at mount, so `liuqin-firmware-path` is `PartOf=` the
  provisioner and a `systemctl restart liuqin-persist-provision` rebuilds
  the union.  `POST_PMU: * Main AMP event failed: -13` can still print at
  probe; playback is audible regardless.

### Fingerprint (FPC1264)

The sensor sits in the power button and the vendor's secure-world application
(the `fpcliu` trustlet) owns it: the kernel side is only a power/reset/IRQ
control interface (`fpc1020`, patch 0018) plus the QSEECOM TEE transport that
lets the runtime talk to the trustlet (patch 0017).  Matching happens inside the
trustlet, never in Linux.

- **Enrolment and unlock: verified** (2026-10-06).  Settings -> System -> Users
  -> Fingerprint Login -> Add walks the trustlet through 20 accepted samples
  (the dialog shows progress plus "lift and reposition" hints), fprintd stores
  the template in its file store, and the Users row reads Enabled afterwards.
  The lock screen verifies through `gdm-fingerprint` (nixpkgs' stock
  `pam_fprintd`) and unlocks on a match; the same run committed an adaptive
  template update, which is how the matcher improves with use.
- The trustlet authorises a template with the account credential input
  (PBKDF2-HMAC-SHA256 over the Linux password, 32 bytes, schema 1).  fprintd's
  Enroll API cannot carry a secret, so `pam_liuqin_fpc` derives it while the
  account password is being authenticated (login/`gdm-password`, `sudo`,
  `polkit-1`) and caches it exactly like the OEM bundle's `acceptance_input`:
  root UID keyring, 18 h, one use, boot-local, nothing on disk.  The very first
  enrolment additionally needs the one-time Gatekeeper credential
  (`liuqin-fpc-credential --create <user>`, root plus a local terminal).
- **One finger per account.** The TOD driver refuses a second print because
  fprintd selects a single print for a device without 1:N identification;
  delete the existing finger in Settings before enrolling another.
- The TOD driver implements verify and enroll but no identification: a rejected
  capture (a tap instead of a firm press) becomes a retry, and a
  `match_result=not_matched` is a real mismatch - use the enrolled finger.
- Two constraints that later bumps must keep: the adaptive-template commit
  (`oem-update.inc`) only accepts a stored template that is 0600, so the daemon
  runs with `UMask=0077`; and the driver's `nr_enroll_stages` must match the
  trustlet's sample count (20), because fprintd stops forwarding progress and
  retry hints once completed_stages reaches it.
- Not implemented: more than one finger per account (above), syncing the
  credential after a password change from the desktop (the CLI entry
  `liuqin-fpc-credential --sync-password <user>` exists for it), the OEM
  acceptance/acceptance-record flow, and fingerprint authentication for the
  `su`/SSH PAM stacks.
- The OEM userspace (the component's own sources: the static QSEE clients, the
  python entry points and the TOD driver) is vendored under
  `pkgs/fingerprint/fpc-oem-src/` (originally yzddmr6/xiaomipad-6pro-mainline
  PR #11; see NOTICE for the revision and licenses); QCBOR and qsee-supplicant
  are pinned from their own upstream tags, and the port's adaptations are the
  patch files next to them.
- The firmware images (`fpcliu.mdt` plus its segments) and the Gatekeeper/RPMB
  state are per-device data and are not in this tree; "Fingerprint" in
  `docs/INSTALL.md` documents the extraction, placement and operator steps.

### USB3 device (peripheral data path)

**verified** (2026-10-07, full-feature kernel): with a USB3 host port and a
USB3 cable, the device side reports
`a600000.usb: maximum_speed=super-speed, current_speed=super-speed` and the
host `lsusb -t` shows the NCM function at **5000M**; `usb0`/NCM works over
the link.  The same cable on a USB2 port/cable only reached 480M.  Status is
read from the link negotiation, not from a throughput benchmark.

Open: a recorded 10-hotplug stability run and a USB2-cable downgrade retest.

### Type-C host and OTG

**verified** (2026-10-07): with a Xiaomi 15 phone attached, the tablet
enumerates it at **5000M** (`usb 2-1: new SuperSpeed USB device … using
xhci-hcd`); with the tablet as host/source it discharges **−2.886 A** into the
phone, so the OTG VBUS path works.  The charger → phone-as-device →
phone-as-host sequence of role changes completes cleanly, and XHCI reclaims
the bus when the phone is the device.

- `data_role`/`power_role`/`usb_role` come from UCSI (`/sys/class/typec/port0`);
  orientation comes from the charger service's `XM_PROP_CC_ORIENTATION`,
  because the ADSP reports UCSI 1.0.0 (no orientation field).  Patch 0005
  reads it and drives the QMP combo PHY's typec switch
  (1 = CC1/NORMAL, 2 = CC2/REVERSE).
- `pm8350_l1` (combo-PHY `vdda-pll`) must be ≥912 mV; the DT pins it there.
- Open: a stated 10-hotplug record, and **automatic gadget unbind/rebind**
  across Host↔Device transitions.  Today, if the debug gadget fails to
  re-bind, restart it from Wi-Fi SSH:
  `systemctl restart liuqin-usb-gadget liuqin-usb-shell`.
  No verified Host VBUS/OCP automatic fallback exists.

### DP Alt Mode

**verified** (2026-10-06, retested 2026-10-07 on the full-feature kernel):
a USB-C→DP adapter drives a 2560x1600 monitor; `card0-DP-1/enabled=enabled`,
`modes = 2560x1600`, link trained (2-lane HBR2, wide bus 2 px/clk, vendor
behaviour).

Known limits:

- **Single-link-rate tables.** The combo-PHY DP serdes/TX tables are the live
  register state of the vendor stack captured at **HBR2 4-lane,
  2560x1600@60, widebus**.  The per-rate (RBR/HBR/HBR3) tables are NULL, so
  the PLL keeps the HBR2 programming; other link rates/monitors are
  unsupported.  Adding one means capturing the vendor's registers at that
  rate the same way (`FIXME(dp-link-rates)` in
  `pkgs/kernel/replaced/phy-qcom-qmp-combo.c`).
- The DT declares **2 data lanes** only; 4-lane DP is not implemented.
- Repeated DP/PD hotplug (10×) and long-run stability are unverified.

### Standard PD and PPS

The deployed kernel has **no AP-side PD stack**: PD/PPS is negotiated by the
ADSP.  The AP can only write `input_current_limit`, and the charging tier is
derived from `usb_type` + `pd_verified` + `power_max`.  Measured on hardware
(2026-10-06/07): an unauthenticated standard PPS contract gives ~8.4–8.5 V
at ~5 A (≈38–45 W) into the battery.  Standard PD/PPS therefore works in
practice; formal acceptance (5 V fallback, PDO/PPS visibility, hotplug) is
**unverified**, and there is no AP-side PDO/PPS control.

### Xiaomi MiPPS (67 W)

**verified** (2026-10-07): with the original 67 W charger and the key files
installed, the daemon completes automatically — `pd_verifed=1`,
`adapter_svid=2717`, `adapter_id=0000a819`, `authentic=1`,
`slave_authentic=1`, `usb: 9.10 V / lim 6 A`, battery current rising from
8.4 to **8.654 A** (~34 °C, SOC 66 %), comparable to the Android golden run
(8.94 V, 6 A, −8.69 A).  Without keys the verdict stays `pd_verifed=0`
(negative control, 2026-10-06).  `reverseAuth` (command 8) is
**unverified**; the daemon correctly does nothing against a phone
(`pdo2 == 0`).

Details and the key contract are in §2.

### Sensors

The SSC/SLPI path is implemented: the package serves the registry contract,
the persist import is atomic, and bounded `libssc` checks cover acceleration,
angular rate and the default SSC ambient-light Lux instance.  In the
installed system the boot chain is `liuqin-slpi` -> `liuqin-hexagonrpcd-sdsp`
-> `liuqin-ssc-sample-gate` -> patched `iio-sensor-proxy`
(`net.hadess.SensorProxy`).  The gate fails closed unless a real accelerometer
sample arrives (`--all --attempts 4 --require accelerometer`); the gyroscope
and light checks are recorded but cannot fail the unit, and the claim-refresh
helpers restart the proxy once a gnome-shell is watching.

**Measured** (2026-10-07, this unit, the boot after a reboot): all three
checks report ready (accelerometer 182 and gyroscope 139 measurement lines in
the gate's window; light one line, 41.9 lx — 28 lx on the previous boot), and
the D-Bus API reports `HasAccelerometer=true`, `HasAmbientLight=true`,
`HasProximity=false`.  Rotating the unit through the four orientations and
the five tilt states is reflected in
`AccelerometerOrientation`/`AccelerometerTilt` (polled at 0.5 s:
`right-up`, `normal`, `left-up`, `bottom-up`; `vertical`, `tilted-up`,
`tilted-down`, `face-up`, `face-down` all observed).

Mount matrix: `libssc` multiplies the SSC registry's matrix into every sample
itself and logs `Mount matrix provided by firmware is all 0, falling back to
identity matrix!` twice per proxy start — this unit's registry carries an
all-zero matrix, so that layer is the identity, and the effective transform
is the udev `ACCEL_MOUNT_MATRIX=-1,0,0;0,-1,0;0,0,1` on `fastrpc-sdsp` that
`iio-sensor-proxy` applies on top.  Verified against the raw vector
(X=+8.54 m/s², Z=+5.72): the signed matrix gives `portrait_rotation = -56.2°`
(`right-up`), the identity would give `+56.2°` (`left-up`).

Sensor claims are polkit-gated to `subject.local` sessions, so
`monitor-sensor --accel` and `ClaimLight` are denied from an SSH session by
design, and `LightLevel` only advances while a local client holds the claim
(GNOME never claims the light sensor, so it reads 0).

**Not done:**

- **The gyroscope has no userspace consumer.**  Real samples arrive through
  the gate, but `iio-sensor-proxy` 3.9 exposes no gyro API and nothing else
  in the image reads `/dev/fastrpc-sdsp` directly.
- **Ambient light: bridged, unclaimed, uncalibrated.**  CCT/RGB is **not
  implemented** (the stock calibration records have no API in the pinned
  `libssc`), and the light check does not distinguish the front TCS3701 from
  the rear TSL2522 — only the default ambient-light instance is used.
- **No fusion.**  The Android-derived gravity/rotation-vector/step/tilt/
  motion behaviours are not implemented; only the accelerometer, gyroscope
  and light instances are opened.  `ssc-compass` sits in the udev
  `IIO_SENSOR_PROXY_TYPE` list, but the proxy has no compass API and no
  magnetometer instance is opened, so that type is inert.
- The accelerometer's magnitude at rest reads ~4.8 % above 1 g (~10.28 m/s²
  for X=8.54, Z=5.72) and the scale is 1.0; nothing calibrates it.
- No suspend/resume or long-run record: the gate runs once per boot, and the
  stack's behaviour across the lid-suspend churn
  (`TODO(lid-suspend-loop)`) is unverified.
- `/sys/bus/iio/devices` can be empty because these devices are owned by
  SLPI, not an AP-side IIO bus.

Operator checks: `sudo liuqin-sensor-check --all --attempts 2` (root, for
`/dev/fastrpc-sdsp` and `/run/liuqin-sensors`; the gate's own logs are
`/run/liuqin-sensors/ssccli-*.log` with the `*-status`/`*-ready` markers),
and `busctl --system get-property net.hadess.SensorProxy
/net/hadess/SensorProxy net.hadess.SensorProxy AccelerometerOrientation
AccelerometerTilt HasAmbientLight LightLevel`.

`hardware.liuqin.sensors.sscConfigHash` must be set (a config-only archive is
accepted; `sns_reg.conf`/`sns_reg_version` are synthesized when absent) or
the build fails.

### Wi-Fi, Bluetooth, storage, power

- Wi-Fi (ath11k/WCN6855) associates and Bluetooth works (**verified**
  2026-09-29), with repeated `msdu_done` errors and occasional carrier
  reconnects.  WLAN MAC and BT public address are per-device values
  provisioned from persist.
- **TODO(wifi-5ghz-rf)**: the 2.4 GHz link is healthy on this unit while the
  5 GHz receive path sits far below expectation.  **Measured** 2026-10-07
  (full-feature kernel, same minute and position, same AP `CMCC-Z6bX`, the
  host as the reference client): 2.4 GHz `ch6` -43/-44 dBm with 0 % ping loss
  against 5 GHz `ch161` -85..-88 dBm with 50 % ping loss; the reference
  (Intel AX210, same AP) reads about -62/-76 dBm, and on a second 5 GHz AP
  (Ciallo `ch44`) the tablet reads -77 dBm where the reference reads
  ~-55 dBm.  `station dump` shows both 5 GHz chains weak (`[-89, -90]`)
  against one strong 2.4 GHz chain (`[-76, -44]`), i.e. the tablet's own
  band-to-band spread is ~40 dB where ~6-12 dB is physical.  Association
  itself works (ch161, VHT-MCS2/NSS2, PTK=CCMP), so this is margin, not a
  functional break.  Ruled out: RF rails (live `pm8350_s11` 952 mV / `s12`
  1256 mV / `pm8350c_s1` 1888 mV, patch 0020 active), regdomain (driver
  self-managed `CN`; every enabled 5 GHz channel is `no IR`, which removes
  active scanning only) and TX caps (AP limits 30/27 dBm).  Resolved by
  `TODO(ath11k-fw-shadowed)` below: the chip had been booting the compressed
  `.zst` firmware/BDF set, and with the vendor set installed at the plain
  paths the same antennas hold `ch161` at -48 dBm with 0 % loss.  The
  `802-11-wireless.band=bg` pin that the tablet's local
  `CMCC-Z6bX.nmconnection` carried as the workaround has been dropped - NM
  selects `ch161` on its own now.
- **TODO(ath11k-fw-shadowed)**: the firmware package ships two ath11k sets
  and the kernel only reads the `.zst` one.  The firmware loader expands
  `updates/` only under its hardcoded `/lib/firmware*` entries
  (`drivers/base/firmware_loader/main.c`, `fw_path[]`), and the custom
  `firmware_class.path=/run/firmware` has no such sibling, so the live set is
  `ath11k/WCN6855/hw2.x/*.zst`: `amss` `WLAN.HSP.1.1-03125-…SILICONZ_LITE-
  3.6510.37` and a 131-entry `board-2` (entry for `17cb:0108 / chip 18 /
  board 255`: 60036 B, `e9c3d433…`).  The unread `updates/` set instead
  carries `amss` `WLAN.HSP.2.0.c2-00057-…696964.3` (stock's branch is
  `…c2-00057-…570200.7`) and a 108-entry `board-2` whose matching entry is
  59920 B, byte-identical to the stock ROM's `bd_m81.elf`.  **Measured**
  2026-10-07 with both sets installed at the plain paths and a PCI
  unbind/bind re-probe: the vendor set boots and its scan sees `shebang-5G`
  `ch36` -64 dBm and `Seeker` `ch36` -78 dBm, neither of which the `.zst`
  set can see; but the vendor `board-2` with the LITE `amss` dies
  (`-110` → `firmware crashed: MHI_CB_EE_RDDM`, reproduced), so the four
  files must stay a set, and under the vendor set NetworkManager still fails
  activation (`set-hw-addr … failure 99`).  Fix: ship the vendor set at the
  plain `ath11k/WCN6855/hw2.1/` paths (first search path wins over `.zst`),
  then settle the NM/MAC wrinkle and re-run the 5 GHz margin table above.
  Implemented in `pkgs/firmware.nix` (both hw dirs, as a set) with the
  scan-MAC randomization disabled in `modules/liuqin/identity.nix` for the
  `set-hw-addr` failure, and **verified** 2026-10-07 after a deploy + reboot:
  `fw_build_id` is the vendor build, `ch161` associates at -48 dBm (signal
  avg -48, beacon -46, chains `[-59, -48]`, tx retries/failed 0) with 0 %
  loss on 20 x 1200 B pings, and the link ramps to VHT-MCS7/NSS2 80 MHz
  (526-650 Mbit/s tx) once the profile's `band=bg` pin is dropped; the scan
  now lists the 5 GHz APs the `.zst` set could not see.
- Bluetooth runs the stock QCA6490 payloads.  The mainline driver asks for the
  `wcn`-prefixed rampatch/NVM names first, and only linux-firmware ships those,
  so `pkgs/firmware.nix` installs the stock `qca/hp*` files under both names;
  before that the controller silently ran linux-firmware's build
  (`BTFW.HSP.2.1.0-00660-USB_UART_PATCHZ-6`) instead of the stock
  `00570-PATCHZ-1` the unit's own `bluetooth_a` partition carries (**measured**
  2026-10-06).  The controller is unconfigured on every boot (volatile
  address), so `liuqin-bt-preconfigure`'s Set Public Address re-runs the whole
  QCA setup and its firmware download; the unit is therefore ordered after
  `liuqin-firmware-path`, without which that download finds no `qca` file
  (the stage-2 root has calibration only) and Bluetooth never starts.
- The WCN6855 RF rails are pinned to the stock DTB's `qcom,init-voltage`
  values (`pm8350_s11` 952 mV, `pm8350_s12` 1256 mV, `pm8350c_s1` 1880 mV).
  The RPMh driver has no `qcom,init-voltage`, and the core's `apply_uV`
  programs the **low** end of the DT range, so the board DTS previously left
  `pm8350_s11` - the BT/WLAN PMU's 0.8/0.95 V domain, per the vendor's
  `bt-vdd-rfa-0p8/rfacmn/aon` supplies - at 384 mV.  **Measured** 2026-10-06
  with the same stationary speakers: mainline -70..-78 dBm vs -56..-60 dBm on
  stock Android, and BT only linked with the device touching the tablet.
  The vendor's `btpower` driver sets these rails explicitly at BT power-on
  (`regulator_set_voltage(vreg, min, max)`), which is what the stock DT's
  init voltages encode.
- The stock BT HAL additionally writes a per-chip NV/RF table to the
  controller at every Bluetooth enable (154 vendor commands, captured from
  the unit's own HCI traffic into the table checked in at
  `pkgs/bt-nv/liuqin-bt-nv.table`).  Mainline's driver only
  downloads the rampatch/NVM files, and without the table - with identical
  rampatch/NVM, board file and rail voltages - the ATK mouse only linked while
  touching the tablet, while the same mouse worked 1 m away on stock Android
  (**measured** 2026-10-06).  `liuqin-bt-nv` (`pkgs/bt-nv/default.nix`, installed on
  PATH) is a manual operator tool that replays the table.  It is deliberately
  not a service, and that is also the honest state of the fix: the table lives
  in controller RAM, the writes are what made the difference in the A/B
  against stock Android, and the tool re-runs in a couple of seconds.  Re-run
  it after any Bluetooth power toggle - the kernel re-downloads the
  rampatch/NVM on every controller open (`HCI_QUIRK_NON_PERSISTENT_SETUP`) and
  that reset wipes the table, including the asynchronous reconfigure setup
  `liuqin-bt-preconfigure`'s Set Public Address triggers (**measured**: table
  at 11.5 s, setup still running until 12.3 s, so a table written at boot is
  wiped again).
- UFS, GPU, PCIe/WCN6855 (needs patch 0010's cape tables) and the initrd
  storage guard work (**verified**).
- Video decode (Iris VPU, patch 0006): H.264 and HEVC decode 1080p30 to bytes
  identical to a software decode, every frame, with the `iris` IRQ line rising
  by ~260 per run (**verified** 2026-10-07); the encoder exposes H.264/HEVC.
- **FIXME(vp9-first-frame)**: VP9 hardware decode loses the first frame of
  every stream.  **Measured** 2026-10-07: a 30-frame 1080p30 clip yields 29
  frames, and those 29 are byte-identical to frames 2..30 of the software
  decode (`hw_md5 == sw_skip1`, `sw_first29` differs), so the missing frame is
  the stream's first.  Reproduced with `-auto-alt-ref 0 -lag-in-frames 0`, so
  it is not a hidden/alt-ref frame being filtered out.  H.264 and HEVC through
  the same element and device lose nothing, which puts the loss in the
  start-of-stream path only VP9 needs (its stream parameters exist only after
  the first frame); the VP9 runs also trip
  `gst_structure_remove_field: assertion 'IS_MUTABLE (structure)' failed` in
  gst-plugins-good, and the other codecs do not.  Impact: ~33 ms per stream -
  playback and transcode are unaffected, frame-accurate checks are not.
  Next: count buffers inside the element (`GST_DEBUG=...`) or cross-check with
  an ffmpeg built with `v4l2m2m` (nixpkgs' ffmpeg has no v4l2-m2m) to decide
  between gst-plugins-good and the iris start path, then patch that side; no
  kernel change is expected.
- AV1 is deliberately not advertised for sm8450: the VPU2 firmware has no AV1
  decoder, and an AV1 session makes it raise `qcom-iris aa00000.video-codec:
  received system error of type 0x5000003`, which takes the whole core down
  and leaves the machine unresponsive (**measured** 2026-10-07 across two
  boots; the driver then trips the vb2 `start_streaming()` cleanup WARN).  The
  gate is `iris_fmts_sm8450_dec` in patch 0006 - do not point sm8450 back at
  `iris_fmts_vpu3x_dec`, which carries AV1 for the VPU3 platforms.
- **TODO(lid-suspend-loop)**: closing the folio cover turns into a
  suspend/resume loop.  **Measured** 2026-10-07: `Lid closed.` 11:17:04 →
  `Lid opened.` 11:41:09, 15 suspends in the window, resume → next
  `Suspending...` 27.3-27.8 s on all 14 cycles (the sleeps themselves are cut
  short after 3-162 s by a wake source that is still unidentified).  The pace
  is logind's own lid recheck, not a client: while the lid is closed
  `button_recheck()` re-runs the lid action on every event-loop turn, gated
  only by `HoldoffTimeoutUSec` (30 s, re-armed on every sleep start; monotonic
  time stops during suspend, hence ~28 s).  `Suspending...` is logind's own
  message (`handle_action_execute()`; the D-Bus `Suspend()` path does not log
  it), so there is no requester to identify - the earlier reading of that line
  as an unidentified D-Bus request was wrong, and `liuqin-power-keyd` staying
  silent fits it.  USB cannot be the waker either (the host sees the device
  disconnect and dwc3/USB wakeup is disabled), so "ignore USB wakeups while
  docked" is a no-op; `HandleLidSwitchExternalPower`/`Docked` never apply here
  (no external power reported while on the cable, no external display).  Per
  cycle the host sees the gadget re-enumerate (`usb 1-2: new high-speed USB
  device`), ath11k re-downloads firmware (`mhi0: Requested to power ON`,
  `chip_id`/`fw_version` again), NetworkManager re-associates
  (`DEAUTH_LEAVING` from the suspend path) and the touch controller re-flashes
  its firmware (`nvt_update_firmware … #20`).  Next: identify the waker with
  `CONFIG_PM_DEBUG` (`/sys/power/pm_wakeup_irq`) or `/proc/interrupts` deltas,
  then decide the cover policy - mechanics, wake-source inventory and the
  options are in `docs/TODO/LID-SUSPEND-LOOP.md`.
- **TODO(rootfs-ext4)**: the root filesystem reports
  `EXT4-fs error (device sda36): ext4_validate_block_bitmap: bad block bitmap
  checksum` at switch-root and again at 11:33 (**measured** 2026-10-07;
  `initial error at time 1773777354`).  Run `fsck.ext4` on the `linux`
  partition from the RAM installer and decide whether the storage guard
  should fail closed on it.
- CPU: cluster capacities 277/832/1024 (expected 278/833/1024), EAS active,
  `teo` idle governor, CPU thermal cooling maps in place (**verified**).
  `CONFIG_UCLAMP_TASK` is not enabled (free to enable, useless until
  something sets hints).  Panel refresh control and IPA are the open energy
  items.
- Thermal is partial: 38 zones (battery, TSENS CPU/GPU, video, memory,
  camera, CDSP, PMIC); Android had 81 including vendor charger/wifi/xo/ddr/
  flash/connector zones that do not exist under those names here.
- Fingerprint: **verified** (2026-10-06) for the desktop flow - enrolment from
  Settings and lock-screen unlock, with one finger per account.  Operation is in
  `docs/INSTALL.md` (Fingerprint) and the limits are in "Fingerprint (FPC1264)"
  above.

### Kernel command line and config inputs

Installed-system `APPEND` (the loader adds `init=` and `root=`):

```text
qcom_q6v5_pas.slpi_auto_boot=0 rootwait initcall_blacklist=simplefb_driver_init
earlycon=simplefb console=tty0 firmware_class.path=/var/lib/firmware
root=fstab loglevel=7 lsm=landlock,yama,bpf
```

- `earlycon=simplefb` + `console=tty0` keep a console from the first line;
  `loglevel=7` (NixOS' 4 hid the log).  `keep_bootcon` is **not** in the
  default — it keeps simplefb0 writing over the compositor — and lives behind
  `hardware.liuqin.boot.debug`.
- `firmware_class.path=` takes **exactly one** directory (`fw_path_para` is a
  single `char[256]`, no `:` splitting).  A second `:`-joined path
  invalidates the parameter and every `request_firmware()` fails with `-2`.
  Both call sites point at `/var/lib/firmware`.
- Three config inputs: `pkgs/kernel/config.nix` (structured answers),
  `pkgs/kernel/liuqin-firstboot.config` and `pkgs/kernel/installer.config` (raw
  fragments appended in `postConfigure` before one `make olddefconfig`, then
  asserted against the final `.config`).  `enableCommonConfig` is
  deliberately off.
- The ramoops node is disabled in `pkgs/bootimg/dts/liuqin-abl-boot-overlay.dts` because
  ABL supplies the same region; keeping both overlaps.

## 2. MiPPS key material and the daemon

MiPPS (Xiaomi 67 W) authentication is driven by `/vendor/bin/batterysecret`
on the stock system, **not** by the kernel.  This tree reproduces that state
machine in `pkgs/mipps-daemon.c` on top of the `qcom-battmgr` sysfs ABI
(patch 0005).

### 2.1 Where the keys come from (extraction, no device needed)

The keys are static tables inside the shipped `batterysecret` binary.  The
whole procedure is offline, on the operator's stock dump:

```sh
cd <liuqin-stock-dump>
python3 tools/extract-super.py list images/super.img
python3 tools/extract-super.py extract images/super.img vendor_a /tmp/mipps-keys/vendor_a.img

EROFSS=$(nix build --no-link --print-out-paths nixpkgs#erofs-utils)
"$EROFSS"/bin/fsck.erofs --path=/bin/batterysecret \
    --extract=/tmp/mipps-keys/batterysecret /tmp/mipps-keys/vendor_a.img
sha256sum /tmp/mipps-keys/batterysecret
# 7a450cdd5c1b65f584f470bb31d4c7a3b4c9cfd6b8cab4473dda6a06e084a1e0
```

Then read the tables per `liuqin-stock-dump/re/usb/batterysecret.md` §4.4.
**Important correction:** that document's "file offset == VMA" is wrong for
this ELF; `.data` is `p_offset 0x6490` / `p_vaddr 0x7490`, so
**file offset = VMA − 0x1000**.  Parse the section headers rather than
trusting a hardcoded delta:

| `.data` VMA | file offset | content | output files |
| --- | --- | --- | --- |
| 0x7490 | 0x6490 | FG key table (5 × 32 B) | — |
| 0x7510 | 0x6510 | liuqin's FG key | `fg.key`, `slave-fg.key` |
| 0x7530 | 0x6530 | 10 × 16 B session seeds | `pd-00.seed` … `pd-09.seed` |
| 0x75d0 | 0x65d0 | 10 × 32 B PD HMAC keys | `pd-00.key` … `pd-09.key` |

- `hw_id` comes from `ro.product.device`; liuqin is `hw_id=17`, which the
  `.rodata` jump table maps to `.data 0x7510`.
- The stock daemon selects the FG key only by device, never by FG index
  (0=main, 1=slave), so `fg.key` and `slave-fg.key` are byte-identical; no
  independent slave key exists.

Cross-check the extraction against the two known vectors before deploying:

```text
HMAC-SHA256(fg.key, 00 01 .. 1f) =
  913eaf487f13069effed9a8475a09fbad4d922032791cecf060036fea8daf5c5
HMAC-SHA256(pd-00.key, BE(112233445566778899aabbccddeeff00) || 00002717)
  (first 16 B) = c96e6db1b62b95e17ab46847817ae7b2
```

### 2.2 Where the keys go

They must never enter git, a Nix file or the Nix store (the module asserts
`keyDirectory` is not under `/nix/store`).  Provision them on the tablet:

```sh
install -d -m 0700 -o root -g root /var/lib/liuqin/mipps
install -m 0600 -o root -g root fg.key slave-fg.key pd-0*.key pd-0*.seed \
    /var/lib/liuqin/mipps/
systemctl restart liuqin-mippsd
```

- Directory root:root 0700; each file root:root 0600.  The daemon refuses
  any other ownership/mode.
- `fg.key`, `slave-fg.key`: 32 B.  `pd-00.key`…`pd-09.key`: 32 B.
  `pd-00.seed`…`pd-09.seed`: 16 B.
- `hardware.liuqin.mipps.keyDirectory` (default `/var/lib/liuqin/mipps`) is
  the current delivery mechanism; the historical `LoadCredential` idea is
  **not implemented**.

### 2.3 The daemon

`hardware.liuqin.mipps.enable` (default `false`) is the only USB feature
switch: the kernel and DT carry every board feature at once.  Sub-options:

| option | default | meaning |
| --- | --- | --- |
| `mipps.enable` | `false` | run `liuqin-mippsd` (systemd unit, root) |
| `mipps.keyDirectory` | `/var/lib/liuqin/mipps` | root-only key directory |
| `mipps.dataRoleSwap` | `true` | do the stock "FG first, then switch to host" order |
| `mipps.reverseAuth` | `false` | also send UVDM cmd 8 (community 6→8→7), unverified |

The daemon owns no PDO or voltage; it only drives the narrow qcom-battery
sysfs ABI.  It watches uevents (`POWER_SUPPLY_NAME=usb`, `DATA_ROLE=ufp`),
re-runs on a 5 s poll, and clears stale verdicts on failure/stop.  Verdict
attributes live at `/sys/class/qcom-battery/qcom-battery/*` (one level
deeper than the vendor ABI); writable ones are root-only 0600.

### 2.4 FG / PD protocol essentials

**FG digest (both batteries).**

1. Write `verify_slave_flag` (`"0"`/`"1"`), then a fresh 32-byte random
   challenge as **65 bytes of hex + NUL** to `verify_digest`.  (Writing only
   64 bytes yields a different digest — not a bug, but know it when
   hand-testing.)
2. The ADSP computes asynchronously.  Reading too early returns the just-
   written challenge, then a stale intermediate value.  Poll for up to 2 s
   (50 ms × 40) and compare against `HMAC-SHA256(fg.key, challenge)`;
   write `authentic=1` / `slave_authentic=1` on match.  Measured: stale at
   90 ms, correct by 500 ms — the stock 89 ms sleep is too short for the
   mainline pmic-glink round trip.

**PD / UVDM adapter authentication.**

1. `process_once()` gates: `real_type ∈ {PD, PD_PPS}`, a reachable USB
   supply (`usb` or `qcom-battmgr-usb` online), `current_state = SNK_Ready`.
2. Write `verify_process=1`; read `pdo2` (if `00000000` the partner is a
   phone — do nothing, matching `usbpd_connect_with_phone()`).
3. **Data role order matters.** Run the FG digest while in the sink role
   first, then switch `data_role=host` and wait (≤3 s) for the adapter SVID
   to appear.  The ADSP publishes the Xiaomi vendor SVID `0x2717` **only in
   the host role**, so the stock order (FG → host → UVDM) is required; the
   default `dataRoleSwap = true` implements it.
4. Pick a random index `rand() % 10` to select `pd-NN.key` / `pd-NN.seed`.
   Generate a 16-byte challenge.
5. Send UVDM commands through `request_vdm_cmd` in the stock order
   `1, 2, 3 (null), 4 (seed hex), 5 (challenge hex), 7, 6, 0`.  A single
   timed-out command is **not** fatal (record and continue); the verdict
   comes only from command 5.  Command 8 is never sent by the stock binary.
6. Compare: the HMAC input is **20 bytes** — the 16-byte challenge followed
   by the 4-byte `adapter_id` in big-endian byte order (the first 8 hex
   chars of the displayed value appended as byte pairs).  MAC =
   `HMAC-SHA256(pd-NN.key, msg)`; only the **first 16 bytes** of the 32-byte
   response are compared.
7. Verdict `"01000000"` / `"00000000"` is sent by commands 7 and 6 in that
   order; on success write `verify_process=0` and `pd_verifed=1`.

**Wire byte order.** The `request_vdm_cmd` write path parses each 8-hex-char
group as a big-endian u32 — identical to the vendor driver's BSWAP_32 — so
the kernel must **not** swap again for commands 4/5/8.  Commands 6/7 keep the
`swab32` (the vendor reads them with LE semantics).  The read path formats
four u32 with `%08x`.  Getting this wrong yields a valid-looking MAC compare
that always fails (`-13`).

`reverseAuth` (command 8, community 6→8→7, expects a W32 response, uses the
second half of the MAC) is implemented but **never sent by stock** and
unverified on hardware.

## 3. Debug and deployment methods

### 3.1 No UART: the forensic toolbox

This tablet has no wired serial.  The available channels:

- **Panel.** The DSI panel is the only local console
  (`earlycon=simplefb console=tty0`); a photo is often the only evidence of
  a boot that never reaches userspace.
- **U-Boot cross-reset stage log.** U-Boot records boot stages in DRAM (the
  last page of the framebuffer carve-out, `no-map` for Linux) and the log
  survives a reset, so a run that dies still reports its last stages through
  the next one.  Read it over fastboot:
  `fastboot getvar stagecount`, then `fastboot getvar stage`,
  `fastboot getvar stage1` … (up to 16 older lines; the panel shows only the
  newest eight).
- **U-Boot console record.** `fastboot getvar concount`,
  `fastboot getvar con`, `fastboot getvar con1` … (`liuqin_conlog [n]`
  in the U-Boot shell dumps/clears more on demand).
- **One-shot hand-off facts.** `fastboot getvar diag` reports exception
  level, Gunyah hypervisor presence, control-FDT size/model; `fastboot
  getvar build` identifies the image tag.  The menu's read-only entries
  (GPT probe, ABL log scan) cover partition/slot questions.
- **pstore/ramoops + journald.** The PMIC vWDT resets ~20 s after the kernel
  stops petting it; the lockup detectors bark earlier and panic, and the
  panic plus the stuck task's stack land in the ramoops pstore dump across
  the reset (`ftrace_dump_on_oops=1`).  journald is configured to sync every
  5 s so the last lines survive a reset.
- **Wi-Fi SSH** is the normal channel once userspace is up
  (`hardware.liuqin.debugTransport = "ssh"`, key-only).
- **USB NCM/ECM gadget** covers the "display is dead" case; today that is
  the *installed-system* USB shell or the RAM installer (see §3.2).

### 3.2 USB debug network (192.168.7.2) and `nix copy`

The tablet presents `192.168.7.2/24` over USB (NCM, ECM fallback), serves
DHCP to the host, and runs a busybox **telnet root shell on port 2323**
(sshd on 22 in the installer):

```sh
# host: find the interface, then either let DHCP run or assign an address
ip -4 addr show
sudo ip address replace 192.168.7.1/24 dev <usb-if>
telnet 192.168.7.2 2323
```

On an installed system this channel is opt-in:
`hardware.liuqin.debugTransport = "usb"` (or `"both"` to keep Wi-Fi SSH).
The gadget is fixed at `superSpeed = true, requestDeviceRole = false`
because UCSI owns the Type-C role.  If the cable is unplugged the host-side
interface simply disappears.

Deploying a new system over the local binary cache (the full walk-through is
in `docs/INSTALL.md` §4): serve `/var/tmp/liuqin-cache` from the host, then
on the device set `NIX_CONFIG` with `require-sigs = false` and a
`substituters` line pointing at `http://192.168.7.12:8137`, `nix copy`
the toplevel and loader script, set the system profile, run the loader
script, and `switch-to-configuration boot`.

The same update works over Wi-Fi: substitute the tablet's DHCP address for
192.168.7.2, and either serve the binary cache on an address the tablet can
reach or use the delta transfer (`nix-store --export`/`--import`, measured
2026-10-06: 360 MB in ~10 s over the USB link) instead; `docs/INSTALL.md` §4
lays both out.  `examples/demo/configuration.nix` marks the demo user a
trusted user, which
is what direct `nix copy --to ssh-ng://demo@<tablet-ip>` deployments rely on.

### 3.3 Kernel module probe method (dp-dump)

The DP Alt Mode bring-up used a purpose-built **read-only probe module**
that dumps PHY/DP-controller registers and node clock rates, compiled for
both sides (vendor 5.10 Android and mainline 7.2.5) from one source:

- It walked the DT `reg-names` windows and exposed them under
  `/proc/liuqin_dp_dump`, with a `window=N` module parameter to read one
  window at a time and `sync` after each, so a window that hangs the bus
  does not lose the earlier data.  It also printed each node's clock rates.
- On Android it was built against the vendor 5.10 tree with
  `.scmversion`/`KERNEL_RELEASE` faked to the running kernel's vermagic and
  with `__versions` CRCs rewritten from the device's own modules
  (`extract-stock-crcs.py` + `fix-module-crcs.py`); `dp-dump-adb.sh arm|fetch`
  pushed and collected it.  Diffs between vendor-live and our registers
  (`dp-reg-diff.py`) distinguished stable configuration differences from
  dynamic state, and `dp-gen-vendor-tables.py` generated the C tables that
  are now in `pkgs/kernel/replaced/phy-qcom-qmp-combo.c`.
- **The probe was removed from this repository during consolidation and is
  archived under `liuqin-audit/kernel-exp/dp-dump-probe/`** (source,
  `Makefile`, `default.nix`), together with the build/collect scripts
  (`build-dp-dump-probe.sh`, `dp-dump-adb.sh`, `dp-reg-diff.py`) and the
  table generator (`dp-gen-vendor-tables.py`) in `liuqin-audit/kernel-exp/`;
  the captures and the golden register data are under
  `liuqin-audit/out/dp-vendor-golden-20261006/`.
- **Safety rules, measured twice:** never read the dp-GDSC window
  (`0xaf09000`) while DP is streaming — it hangs the bus and forces a hard
  reset; and never poll the DP connector's `status`/`modes` (they call
  `detect()`; a 2 s poll is enough to wedge the display stack).  Use the
  cached `card0-DP-1/enabled` as the trigger, and per-window `sync`.
- A failed DP enable can leave the DPU encoder waiting for frame-done and
  wedge the session into a reboot, so capture with `dmesg -w` redirected to
  a file under `/var/tmp`.

## 4. Kernel patch series

`pkgs/kernel/default.nix` applies every `pkgs/kernel/patches/*.patch` to a pristine
7.2.5 tree in **byte-sorted filename order**, except the patches listed in
its `dtPatchNames` (`0014-…`/`0015-…`/`0016-…` today), which are applied
last.  The 16 patches are grouped by subsystem; the first 14 were merged down
from a 33-patch bring-up series (the provenance is in each patch header),
producing a byte-identical tree, and 0015/0016 add the WCD9385 capture graph
and the CS35L41 amplifier naming.

### The 16 patches

| # | patch | what |
| --- | --- | --- |
| 0001 | `board-dts-bindings` | board DTS, compatibles/bindings, sm8450/sm8475 dtsi fixes, dtb Makefile entry |
| 0002 | `input-hid-touchscreen` | Nanosic WN8030 keyboard folio + Novatek NT36xxx touchscreen |
| 0003 | `display-panel-msm` | NT36532 DSI panel, msm dirtyfb fix, warm-start fixes (stop the DSI controller, no bootloader-PLL replay) and one early DPMS off/on after the first modeset |
| 0004 | `audio-audioreach` | audioreach/sc8280xp path, cs35l41, wm_adsp, q6apm |
| 0005 | `power-pmic-glink-mipps` | PON/pmic-glink + qcom_battmgr MiPPS ABI and CC orientation |
| 0006 | `media-iris` | IRIS VPU platform for sm8450 |
| 0007 | `soc-misc-earlycon` | UBWC table, earlycon-simplefb, quiet q6v5 handover |
| 0008 | `usb-typec-dp` | eUSB2 repeater PHY, sm8450 combo-PHY tables, UCSI PPM reset, vendor SVID altmode, DP link-capacity fix |
| 0009 | `pinctrl-sm8475` | sm8475 TLMM driver + gpio-function flag |
| 0010 | `pcie-qmp-phy` | QMP PCIe PHY cape tables (without them the PHY times out and WCN6855 never enumerates) |
| 0011 | `cpu-topology-thermal` | board CPU capacity/energy model + sm8450 thermal cooling maps |
| 0012 | `camera-core` | CAMSS sm8475, sensor drivers, board camera DTS |
| 0013 | `camera-tuning` | s5kjn1 vendor modes/vflip, gt9764 autofocus, camcc/gcc GDSC always-on |
| 0014 | `board-usb-typec-dp-dt` | board DTS for USB3 device, Type-C host/OTG and DP Alt Mode |
| 0015 | `audio-wcd-capture` | WCD9385 RX/TX SoundWire capture graph, guarded UCM `Mic`, 2.75 V micbias — **applied after 0014** |
| 0016 | `cs35l41-subsystem-id` | name the four CS35L41 amplifiers so the driver picks linux-firmware's Halo build keyed by 10251826 — **applied after 0015** |

### Why 0014, 0015 and 0016 are applied last

The board DTS is built up in layers: 0001 creates it, 0011 and 0012 extend
it, and 0014 adds the USB/Type-C/DP nodes (connector, FSA4480 SBU mux,
912 mV PLL rail) on top.  `pkgs/kernel/default.nix` keeps 0014 in `dtPatchNames`
so it is applied after the sorted series; the earlier USB3/Type-C/DP DT
patches could not coexist as separate patches because they add the same
`pm8350_l1` regulator and `&usb_1_qmpphy` node and the Type-C `&usb_1` hunk
rewrites the node USB3 had changed, so they were merged into this one patch
generated against the post-common tree (zero fuzz).  0015 and 0016 are in
the same list because they extend the same board DTS (the WCD9385 codec with
its capture links and audio routing, and the amplifier `cirrus,subsystem-id`
overrides), so they are applied after 0014 as well.

### One file is replaced, not patched

`pkgs/kernel/replaced/phy-qcom-qmp-combo.c` is copied over the tree in `postPatch`.
The DP side of the combo PHY is a wholesale replacement whose values are the
vendor's live register state; upstream shares the same DP block between the
`sm8350` and `sm8450` cfgs, so a unified diff cannot distinguish them and
patch fuzz would hit the wrong cfg.  The file is generated by
`liuqin-audit/kernel-exp/dp-gen-vendor-tables.py` plus the COM/PD_CTL fixes
(see §3.3).

### Config assertions, not just patches

- `pkgs/kernel/check-patch-hunks.py` runs in `postPatch` and fails the build if a
  patch's declared hunk counts do not match its body (GNU patch silently
  truncates a short hunk — the bug that once dropped `&usb_1`/`&usb_1_hsphy`
  and left the installed system with no USB debug channel).
- The three config inputs (`config.nix`, `liuqin-firstboot.config`,
  `installer.config`) are appended in `postConfigure`, re-resolved with
  `make olddefconfig`, then asserted: every `CONFIG_X=y` must survive as
  `=y` and every `CONFIG_X=m` as `=y|=m` (`ZRAM` is an exact-`m` exception).
  `postBuild` also asserts `fw_path_para` survived into `vmlinux`.
- The full build asserts the camera config symbols against the final
  `.config` via `pkgs/kernel/camera-symbols.txt`.

### Adding or regenerating a patch

Use a scratch git repo of only the files the series touches and let git
produce the diffs (full recipe in `pkgs/kernel/patches/README.md`):

```sh
mkdir /tmp/kfix && cd /tmp/kfix
grep -h '^+++ b/' pkgs/kernel/patches/*.patch | sed 's|^+++ b/||' | sort -u > paths.txt
tar -tJf linux-7.2.5.tar.xz > members.txt
awk 'NR==FNR{m[$0]=1;next}{if (m["linux-7.2.5/"$0]) print "linux-7.2.5/"$0}' \
    members.txt paths.txt > extract.txt
tar -xJf linux-7.2.5.tar.xz -T extract.txt && cd linux-7.2.5
git init -q && git add -A && git commit -qm pristine
for p in $(ls <patchdir>/*.patch | sort); do patch -p1 --batch -N < "$p"; done
git add -A && git commit -qm target
# regenerate a group as one diff between two commits:
git diff <before> <after> > 00NN-liuqin-<group>.patch
```

Verify by replaying the regenerated patches onto a pristine checkout and
requiring `git diff <target> HEAD` to be **empty**; run
`python3 pkgs/kernel/check-patch-hunks.py pkgs/kernel/patches/*.patch` and
`nix build .#kernel` before trusting a change.  Keep each patch's prose
header with it.
