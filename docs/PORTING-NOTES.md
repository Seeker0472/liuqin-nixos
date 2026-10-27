# Porting notes: Xiaomi Pad 6 Pro (liuqin, SM8475) on Linux 7.2.5

Current hardware status and the few operational contracts not covered by the
runbooks. Use [INSTALL.md](INSTALL.md) for installation and recovery,
[BOOT-ARCHITECTURE.md](BOOT-ARCHITECTURE.md) for the boot chain, and the linked
`docs/TODO/` notes for open subsystem work. Detailed bring-up chronology,
rejected experiments and the patch inventory are intentionally omitted here.

Status labels distinguish directly recorded tests from the current owner's
confirmation. Tests with pre-OS2.0.4 payloads do not establish acceptance of
the current firmware set.

## 1. What works and what does not

### Summary

| Subsystem | Status | Current limit |
| --- | --- | --- |
| DSI display / DRM / backlight | verified | 120 Hz only; the U-Boot path still uses the early hand-off workaround |
| Touchscreen / pen | owner-confirmed working (2026-10-27) | NVT input devices registered in the read-only snapshot |
| Keyboard folio, touchpad, keys | verified | closed-cover behavior is documented in the lid/suspend note |
| Camera (3 sensors + AF) | verified | one sensor at a time; app recording/JPEG paths remain open |
| Audio playback | previously verified | OS2.0.4 protection and playback need hardware acceptance |
| USB3 device / Type-C host | verified | the 10-hotplug stability record remains open |
| DP Alt Mode | owner-confirmed working (2026-10-27) | no external monitor was attached during the snapshot |
| Standard PD / PPS | measured, not formally accepted | negotiation is ADSP-owned; no AP-side PDO/PPS control |
| Xiaomi MiPPS (67 W) | verified with operator-provided keys | reverse authentication (command 8) is unverified |
| Sensors (SSC/SLPI) | previously partly verified | OS2.0.4 configuration and SLPI behavior need hardware validation |
| Wi-Fi / Bluetooth | previously verified | OS2.0.4 WLAN/BTFM payloads need hardware validation |
| Storage (UFS, root guard) | root guard verified; prior ext4 issue owner-reported fixed | latest retained logs had no matching errors |
| CPU scheduling / Energy Model | verified | — |
| Thermal | partial | 38 zones versus 81 on Android; no IPA |
| Fingerprint (FPC1264) | previously verified | OS2.0.4 firmware needs hardware validation |
| Microphone capture (WCD9385) | previously verified | OS2.0.4 topology needs hardware validation |
| Video (VPU) | partial | VP9 playback loses its first frame |
| U-Boot SuperSpeed | not implemented | U-Boot fastboot is USB2 |

**Read-only device snapshot (2026-10-27).** Xiaomi Pad 6 Pro, Linux 7.2.5,
NixOS 26.11.20260928.7a0f122. `DSI-1` was connected and `DP-1` disconnected;
NVT touchscreen and pen devices were registered, and no systemd units were
failed. `/dev/sda36` was mounted ext4/rw; no matching ext4/I/O errors were
found in retained kernel logs. This was not an offline filesystem check.
The owner confirms DP Alt Mode and touch/pen are working; this session did not
attach a display or generate physical touch input.

### Display

The internal 1800x2880 DSI panel exposes one 120 Hz mode. The U-Boot boot path
still requires patch 0003's early pipeline stop/start and one early DPMS cycle;
this is separate from external DP Alt Mode. Evidence and remaining acceptance
criteria are in
[`DISPLAY-CAMERA-REVIEW.md`](TODO/DISPLAY-CAMERA-REVIEW.md).

### Touch and input

The owner reports touchscreen and pen working; the snapshot above confirms the
NVT input devices are registered. No input failure is currently reported. The
firmware parser's missing range checks are a separate hardening gap, not an
observed touchscreen operation problem.

### Camera

All three modules capture through CAMSS and libcamera's `simple` pipeline.
They share one CSID, so only one camera can stream at a time. AF behavior,
capture limitations and open items are maintained in
[CAMERA-MAINLINE.md](TODO/CAMERA-MAINLINE.md).

### Audio

Four-speaker playback and WCD9385 capture were measured with the prior payload
set. OS2.0.4 AudioReach topology and speaker-protection payloads still need
hardware acceptance. The USB-C headset and digital-microphone paths are not
implemented.

### Fingerprint (FPC1264)

The kernel provides power, reset and IRQ control; matching and credentials
remain in the secure-world trustlet. Prior firmware supported one-finger
enrollment. See [INSTALL.md](INSTALL.md) for local credential provisioning;
the OS2.0.4 firmware still needs hardware validation.

### USB3 device (peripheral data path)

The installed gadget uses NCM with ECM fallback. Its unit retries failed
starts and reports success only after the UDC binds the function. The
10-hotplug acceptance record remains open; the cover-close re-enumeration
issue is tracked in [LID-SUSPEND-LOOP.md](TODO/LID-SUSPEND-LOOP.md).

### Type-C host and OTG

Host mode and OTG power were verified. The remaining 10-hotplug stability
record is separate from basic enumeration; PD/PPS negotiation belongs to the
ADSP, not an AP-side Type-C driver.

### DP Alt Mode

The owner confirms DP Alt Mode working. No external display was connected in
the read-only snapshot above; the earlier device test is recorded in
[INSTALL.md](INSTALL.md).

### Standard PD and PPS

The ADSP negotiates standard PD/PPS. The AP exposes the negotiated state but
does not select PDOs or PPS voltage; formal fallback and hotplug acceptance
remains incomplete.

### Xiaomi MiPPS (67 W)

The daemon requires operator-provisioned key files described in §2. The stock
authentication path is verified; optional reverse authentication is not.

### Sensors

SSC/SLPI previously exposed accelerometer and ambient-light data. The current
OS2.0.4 registry and SLPI behavior still need hardware validation; sensor
fusion and absolute light calibration are not implemented. A root smoke check
is `liuqin-sensor-check --all --attempts 2`; SensorProxy claims are
session/polkit-gated, so SSH reads alone do not prove fresh samples. See
[AUTOMATIC-BRIGHTNESS.md](TODO/AUTOMATIC-BRIGHTNESS.md) for the light-path work.

### Wi-Fi, Bluetooth, storage, power

Wi-Fi and Bluetooth worked with the prior vendor payloads; the OS2.0.4 WLAN
and BTFM files still need validation. The old-payload Bluetooth range
workaround is `sudo liuqin-bt-nv`; controller setup resets its table, so replay
it after each power toggle and after `liuqin-bt-preconfigure` completes.

An ext4 block-bitmap checksum error on `/dev/sda36` was reported through
2026-10-26. The 2026-10-27 retained logs had no matching errors; the owner
reports the issue has since been fixed. The repair method is not recorded here.
Closing the folio locks and blanks the panel but does not suspend, avoiding
the measured suspend/re-wake loop; see
[LID-SUSPEND-LOOP.md](TODO/LID-SUSPEND-LOOP.md).

### Video (VPU)

H.264/HEVC paths are available. VP9 hardware decode drops the first frame
(29/30 frames in the recorded 1080p30 case); the known limitation is marked
`FIXME(vp9-first-frame)` in `pkgs/kernel/config.nix`.

### Kernel command line and config inputs

The current installed command line is listed in [README.md](../README.md).
Kernel configuration ownership and merge rules are documented in
[`pkgs/kernel/CONFIGURATION.md`](../pkgs/kernel/CONFIGURATION.md); avoid
maintaining a second copy here.

## 2. MiPPS key material and the daemon

MiPPS authentication is reproduced by `pkgs/mipps-daemon/` from the stock
`batterysecret` behavior. The daemon is disabled by default and does not own
the negotiated PDO or voltage.

### 2.1 Where the keys come from (extraction, no device needed)

From the operator's stock dump, extract `vendor_a` with
`liuqin-stock-dump/tools/extract-super.py`, then extract
`/bin/batterysecret` with `fsck.erofs` from `erofs-utils`:

```sh
cd <liuqin-stock-dump>
python3 tools/extract-super.py extract images/super.img vendor_a \
    /tmp/mipps-keys/vendor_a.img
EROFSS=$(nix build --no-link --print-out-paths nixpkgs#erofs-utils)
"$EROFSS"/bin/fsck.erofs --path=/bin/batterysecret \
    --extract=/tmp/mipps-keys/batterysecret /tmp/mipps-keys/vendor_a.img
```

Keep the keys offline while extracting them; they must not enter Git, a Nix
expression or the Nix store. For the inspected binary, parse ELF section
headers: `.data` file offsets are not their VMAs (the difference is `0x1000`).
The Liqin FG key is at file offset `0x6510`; PD session seeds start at `0x6530`
and PD HMAC keys at `0x65d0`. Recheck the section layout if the stock binary
changes. The stock daemon uses the same FG key for both batteries, so
`fg.key` and `slave-fg.key` are equal.

Extraction checks: `HMAC-SHA256(fg.key, 00 01 … 1f)` is
`913eaf487f13069effed9a8475a09fbad4d922032791cecf060036fea8daf5c5`;
the first 16 bytes of
`HMAC-SHA256(pd-00.key, BE(112233445566778899aabbccddeeff00) || 00002717)`
are `c96e6db1b62b95e17ab46847817ae7b2`.

### 2.2 Where the keys go

Provision only on the tablet, normally under `/var/lib/liuqin/mipps`.
`hardware.liuqin.mipps.keyDirectory` must not point into `/nix/store`.
The directory must be root:root mode `0700`; key and seed files must be
root:root mode `0600`. Required files: `fg.key`, `slave-fg.key`,
`pd-00.key`–`pd-09.key` (32 bytes each), and `pd-00.seed`–`pd-09.seed`
(16 bytes each).

### 2.3 The daemon

`hardware.liuqin.mipps.enable` defaults to `false`;
`dataRoleSwap` defaults to `true` because the adapter's vendor SVID appears
only in host data role. `reverseAuth` defaults to `false`; command 8 has not
been verified on hardware. Authentication failures restore the device data
role; see `pkgs/mipps-daemon/` for the service and state-machine details.

### 2.4 FG / PD protocol essentials

FG authentication is HMAC-SHA256 over a fresh challenge. PD authentication
switches from sink to host before vendor UVDM commands; the stock sequence is
`1, 2, 3, 4, 5, 7, 6, 0`, with command 5 carrying the response used for the
verdict. The comparison uses the first 16 MAC bytes and a big-endian
`adapter_id`. Command 8 is non-stock and unverified; the daemon source is the
implementation reference.

## 3. Debug and deployment methods

### 3.1 No UART: the forensic toolbox

There is no wired UART. Before userspace, use the panel console and U-Boot
records: `fastboot getvar stagecount` / `stageN`, `concount` / `conN`,
`diag` and `build`. After a kernel panic or watchdog reset, inspect pstore
and the persistent journal. Once userspace is up, key-only Wi-Fi SSH is the
normal channel; the USB gadget is the recovery path when the panel is dark.

### 3.2 USB debug network (192.168.7.2) and `nix copy`

The USB gadget uses NCM with ECM fallback at `192.168.7.2/24`; it provides
DHCP and an unauthenticated root telnet shell on port 2323. Installer SSH on
port 22 is key-only. On an installed system the USB shell is opt-in through
`hardware.liuqin.debugTransport = "usb"` or `"both"`; expose it only to a
directly connected trusted host. Deployment and `nix copy` procedures are in
[INSTALL.md](INSTALL.md).

## 4. Kernel patch series

The canonical patch order is `pkgs/kernel/patches/series`; per-patch purpose,
provenance and regeneration instructions belong in
[`pkgs/kernel/patches/README.md`](../pkgs/kernel/patches/README.md). The
resolved Kconfig policy is documented in
[`pkgs/kernel/CONFIGURATION.md`](../pkgs/kernel/CONFIGURATION.md). The kernel
build checks patch hunk counts and final configuration; do not duplicate its
patch catalog here.
