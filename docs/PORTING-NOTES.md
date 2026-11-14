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
| DSI display / DRM / backlight | usable with the existing boot workaround | 120 Hz only; C2–C9 have not passed first-image acceptance without recovery |
| Touchscreen / pen | owner-confirmed working (2026-10-27); firmware resumes after display recovery | 2026-11-14 display candidates time out at first ReK; second initialization succeeds |
| Keyboard folio, touchpad, keys | verified | closed-cover behavior is documented in the lid/suspend note |
| Camera (3 sensors + AF) | verified | one sensor at a time; app recording/JPEG paths remain open |
| Audio playback | previously verified | OS2.0.4 protection and playback need hardware acceptance |
| USB3 device / Type-C host | verified | the 10-hotplug stability record remains open |
| DP Alt Mode | owner-confirmed working (2026-10-27) | no external monitor was attached during the snapshot |
| Standard PD / PPS | measured, not formally accepted | negotiation is ADSP-owned; no AP-side PDO/PPS control |
| Xiaomi MiPPS (67 W) | verified with operator-provided keys | reverse authentication (command 8) is unverified |
| Sensors (SSC/SLPI) | previously partly verified | OS2.0.4 configuration and SLPI behavior need hardware validation |
| Wi-Fi / Bluetooth | previously verified | OS2.0.4 WLAN/BTFM payloads need hardware validation |
| Storage (UFS, root guard) | root guard verified; ext4 bitmap errors recurred on 2026-11-14 | current filesystem health needs an offline check |
| Standby / LPASS clocks | PM-clock lifecycle corrected; ADSP sleep observed | roughly eight-minute early resume persists; overnight battery life unverified |
| CPU scheduling / Energy Model | verified | — |
| Thermal | partial | 38 zones versus 81 on Android; no IPA |
| Fingerprint (FPC1264) | OS2.0.4 dual-finger gallery enrolled; both fingers matched and a cross-finger attempt mismatched after daemon reload; stock-style IRQ level interface booted and passed no-finger smoke | physical early-press response on new kernel, post-reboot match and production deletion unverified |
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

The internal 1800x2880 DSI panel exposes one 120 Hz mode. The normal fallback
still uses the existing early pipeline recovery and one timed DPMS cycle.
The workspace's 0001/0003 display changes instead give the panel ownership of
five supplies and reset, check backlight writes, and remove the timed cycle;
their first image still fails. C2–C9 experiments must not be presented as a
completed handoff fix. This is separate from external DP Alt Mode.

In the 2026-11-14 stop snapshot, the tablet was running C9 with both
experimental switches disabled and GDM active after controlled OFF/ON. The
next-boot profile had been restored to the normal LPASS-fixed fallback; no
reboot into it was performed after the stop request. Exact system/kernel
identities, failed experiments and evidence limits are in
[DISPLAY-HANDOFF.md](TODO/DISPLAY-HANDOFF.md). The earlier display/camera review
remains in [DISPLAY-CAMERA-REVIEW.md](TODO/DISPLAY-CAMERA-REVIEW.md).

The subsequent [systematic handoff investigation](research/DISPLAY-HANDOFF-2026-11-14.md)
traces the actual ABL/DisplayDxe shutdown and fixed U-Boot exit path, distinguishes
the dump's stock continuous-splash driver from mainline initialization, and finds
PLL bias/mux writes during clock registration before the first modeset. It also
limits several historical exclusions to their actual sampling points and inputs.
This was an offline investigation; it did not deploy a fix or resolve first image.

### Touch and input

The 2026-10-27 owner report and snapshot confirm working touch/pen and registered
NVT devices. In the 2026-11-14 display candidates, the first firmware download
completes but ReK remains at 0xa0; failure leaves IRQ and ESD handling disabled.
After controlled display OFF/ON, the second firmware initialization completes.
DSI1 already has no read response before that boot's touch download, but this
does not establish that the shared TDDI firmware is irrelevant to display startup.
The firmware parser's missing range checks remain a separate hardening gap.

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

LPASS WSA/VA/TX/RX PM-clock backports are now patches 0024–0026. Controlled
battery tests confirm ADSP can sleep after the clock-vote lifecycle correction;
they do not constitute playback or speaker-protection acceptance. Speakers
were not tested in this session, as requested.

### Fingerprint (FPC1264)

The kernel provides power, reset and IRQ control; matching and credentials
remain in the secure-world trustlet. Prior firmware supported one-finger
enrollment. On OS2.0.4, a first attempt failed at `sample` without an
accepted export; the new TOD had imposed an unjustified exact remaining-count
sequence and obscured its own protocol error. With that corrected, one
`right-index-finger` enrolled through fprintd and verified `verify-match`
(2026-10-30/31). A one-shot IRQ counter and post-arm drain could drop early
presses; removing only the drain caused setup IRQs to trigger rejected
captures and verification errors. The current kernel exposes GPIO40's
current level plus sysfs IRQ notifications. The worker uses read-before-poll,
treats a notification as the finger event, and re-reads the level every
100 ms because the line is a short pulse; the TA and capture qualify the
event. On the new kernel a reset produced a sticky
notification and readable level, a no-finger verification waited 15 seconds
without a false result, and the sensor powered off after cancellation.
Enrollment now follows the vendor HAL: `fpc_tee_enrol` status 0 is the only
final-sample signal, `remaining` is diagnostic, fprintd skips its pre-enroll
duplicate-identification scan, and the custody marker is written only at the
final authorization gate so a capture-phase failure stays retryable.
Physical early-press responsiveness and capture-retry handling are not yet
validated on this build. See [INSTALL.md](INSTALL.md).

The stock `vendor_a:/lib64/hw/fingerprint.fpc.so` (SHA-256
`ce2ffe2b1af8587a49a57e52038d330d68d7d5fc564d7f276757cc13e9c9c455`)
exposes template enumeration (TEE 11/8), selective deletion (11/9), the
END_ENROL ID and IDENTIFY's matched ID. A root-private OS2 lab verified two
distinct IDs, removal of only the original ID from a copied two-template
database, and isolated match of the new finger / mismatch of the original
finger on the resulting new-only database. The production cutover uses
a per-user canonical gallery with validated finger-to-ID mapping and a
durable fprintd publisher. On 2026-10-31, `right-thumb` enrolment completed,
both it and `right-index-finger` appeared in `fprintd-list` and each matched
against the combined gallery. Deliberately pressing the index finger while
verifying `right-thumb` returned `verify-no-match` after a daemon reload.
No pending export remained. A later reboot with the IRQ-contract kernel
retained both `fprintd-list` entries; physical matching after that reboot
and production deletion remain unverified.

On 2026-11-01 the operator reported that the latest on-device fingerprint
build was basically usable. The mainline RPMH PLDO table steps by 8 mV:
an exact 3.3 V request returned `-EINVAL` and the rail stayed at 2.96 V; a
fixed-3.3 V boot constraint also failed. The current driver requests the
first supported step at or above 3.3 V (3.304 V) only while the sensor is
open, while the boot/default remains 2.96 V. This runtime change still
needs hardware acceptance; early-press latency, post-reboot matching and
production deletion remain unmeasured.

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
The 2026-11-14 boots again reported `ext4_validate_block_bitmap` errors on
`/dev/sda36`; the earlier report does not establish current filesystem health.
The final C9 boot again reported a bad block-bitmap checksum in group 1445 and
mounting a filesystem with errors; the read-only stop snapshot confirms
`/dev/sda36` is the ext4 root filesystem. No filesystem repair was performed.
Closing the folio requests suspend through logind. The active-session power
controller handles locking/blanking and reopening without unlocking; see
[LID-SUSPEND-LOOP.md](TODO/LID-SUSPEND-LOOP.md). LPASS clock changes allow ADSP
sleep, but roughly eight-minute early resume persists. The 0.620 W LPASS-only
and 0.377 W panel-candidate readings have different battery/session conditions
and cannot establish a saving percentage or overnight endurance.

### Power-key controller

The root `broker.py` owns `pmic_pwrkey` evdev input, active-seat selection,
logind suspend and a virtual device that projects only `KEY_WAKEUP`. It
launches a controller under the selected graphical
session's UID over a private, bounded `SOCK_SEQPACKET` socket. Only that active
worker may request suspend. Input is grabbed once the desktop is ready and
released if the worker or its providers fail. systemd cleans up both processes.
`launch.py` waits for Mutter, reads the user manager's imported configuration
environment under that UID and execs `session.py` before GLib caches directory
paths. This preserves custom
XDG directories, including GDM's per-seat dconf outside its account home. Only
configuration variables are imported; the package schema and code environment
stay controlled by the wrapper. A late session bus/manager is retried while
input remains ungrabbed. The session has no arbitrary input-injection interface.

`policy.py` holds the state machine without device or D-Bus dependencies.
Mutter `PowerSaveMode`, logind `LockedHint` and `PrepareForSleep` are separate
facts. User-session lock and display requests are asynchronous. Locking waits
for `LockedHint`, not a method acknowledgement; an already locked screen
blanks directly. Transaction tokens reject stale replies after a wake cancels
locking/blanking. Once suspend is committed, a further press requests display
wake after resume, with its release consumed. Holding a wake key cannot trigger
another short press. Accepted wake commands first project `KEY_WAKEUP`, so
Mutter sees user activity despite the exclusive power-key grab. They then set
DPMS on, without unlocking. Lid display policy uses this same controller; logind
continues to own lid suspend. No persistent display-state marker is used.

`nix build .#checks.x86_64-linux.liuqin-power-key` runs gesture/race tests and
real Gio calls against a private D-Bus with independently delayed lock replies
and lock-state changes. These checks also run in the native tablet package.
The current suite has 51 tests, including startup environment ordering and
configuration-directory isolation. On 2026-11-14 the Fast build completed four
greeter wake/blank cycles without requesting suspend or bypassing authentication;
each wake reset Mutter's idle timer. The exact prior GSettings value was restored.
The same four cycles passed again after reboot, with the controller's
`XDG_CONFIG_HOME=/var/lib/gdm/seat0/config` and zero service restarts.
With the display confirmed on and the default suspend policy restored, an evdev
power press slept 59.687 seconds and resumed on RTC IRQ 22 (success +1, fail +0).
These tests inject events through the real evdev/session path; physical PMIC-key
wake and folio movements still need manual acceptance. The short RTC test is not
a reliable battery-power benchmark. Records are retained under
`/var/tmp/liuqin-power-environment-{acceptance,suspend-2}-20261114/` on the tablet.

### Battery telemetry

The SM8475 property protocol reports full/design charge in uAh, but its
remaining-charge counter in mAh. Patch 0005 selects charge-domain reads even
though this protocol never sends the BAT_INFO response that would initialise
the unit, converts only the counter to uAh, and exposes that measurement as
both `charge_counter` and `charge_now`. Full/design charge is not rescaled.
The firmware percentage remains available separately.

The SM8475 battery descriptor omits `power_now` (observed as a fixed 10 W
despite varying measured current/voltage) and the firmware time estimates
(units not yet verified). UPower uses `current_now`, `voltage_now` and the
charge attributes to derive energy, power and runtime estimates. Other
Qualcomm variants keep their existing property lists and units.

`nix build .#checks.x86_64-linux.liuqin-battery-telemetry` compiles the actual
patched getter/property map against stock capacity values and the 2026-11-13
charging capture. It also checks signed/overflow cases, transport failures
and isolation from the other protocols. The deployed kernel was verified on
battery: design/full charge 8600000/7593000 uAh, a remaining-charge sample of
5944000 uAh, UPower energy 24.49 Wh, and varying measured power. Charging with
the deployed kernel still needs separate acceptance. A 60-second suspend
sample returned an unchanged charge counter; it does not establish zero power.
Later tests measured charge-counter deltas over roughly eight-minute sleep
windows; their conditions and limits are recorded in
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
