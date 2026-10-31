# Installing, updating and operating a liuqin system

Operational companion to `PORTING-NOTES.md` (what the port does, and its
limits) and `docs/BOOT-ARCHITECTURE.md` (the boot chain and U-Boot menu in
detail).  Debug transports,
forensic channels and the deployment cache are described in
`PORTING-NOTES.md` §3 and are only referenced here.

## 0. The two ways this board boots an OS

|  | **A. U-Boot** (the installed system's normal path) | **B. ABL direct** |
|---|---|---|
| chain | ABL → `boot_b` (U-Boot) → menu → `sysboot`/extlinux → kernel | ABL → `fastboot boot <boot.img>` → kernel |
| display | ABL hands over a *live* pipeline; mainline's in-place take-over lost the picture (white, then black) until the whole pipeline was stopped and started once. Patch 0003 stops the DSI controller, drops the bootloader-PLL replay, and does one DPMS off/on 1.5 s after the first modeset — verified on the unit, the panel lights at ~4.4 s and stays | ABL finds no `/reserved-memory/splash_region` in the boot.img's DT and calls `DisableDisplay()`, which powers the panel down; the first modeset lights it cleanly (~1.9 s) |
| generation selection | yes — the menu lists them | no — one image, one generation |
| used for | daily boots | RAM installer, tests, recovery |

Path A is the product.  Path B is what makes the installer and any
`fastboot boot` test image look good: the flake's kernel DT renames the node
to `linux_splash@b8000000` (patch 0001) exactly so ABL takes its teardown
branch.  On path A the bootloader hands over a *live* pipeline, and patch 0003
stops it and starts it again once (1.5 s after the first modeset, before any
DRM master exists) — verified on the unit 2026-10-07: the console lights at
~4.4 s and stays.

## 1. Host side

- **USB network.**  The tablet is `192.168.7.2/24`; the host is
  `192.168.7.12/24` on the NCM interface (the exact address is whatever
  DHCP hands out for this host; check with `ip -4 addr show`) or
  `192.168.7.1/24` if you assign an address by hand.  The RAM installer
  always brings this channel up; an installed system presents it only when
  `hardware.liuqin.debugTransport` is `"usb"` or `"both"` (see
  `PORTING-NOTES.md` §3.2 for the gadget, the telnet shell and the
  bus/interface details).  If the cable is unplugged, the host-side interface
  (`enp14s0u3` on the reference host) simply disappears.
- **Installed-system debug transport.**  `hardware.liuqin.debugTransport`
  accepts `"ssh"` (default), `"usb"`, `"both"` or `"none"`.  The selector
  enables or disables the installed system's OpenSSH service and USB gadget
  with `mkDefault`, so an explicit `services.openssh.enable` or
  `hardware.liuqin.usbShell.enable` can still override it.  SSH defaults
  `PasswordAuthentication` off, so enroll an authorized key before relying
  on it.  The demo target forces `"both"`
  (`config/demo/configuration.nix`), keeping Wi-Fi SSH while exposing the
  USB deploy link.
- **Binary cache for pushes.**  A plain `python3 -m http.server 8137 --bind
  192.168.7.12` serving `/var/tmp/liuqin-cache` (reference host process name
  `liuqincache`).  Fill it on the host with `nix copy --to
  file:///var/tmp/liuqin-cache <store paths>`; the device then copies from
  `http://192.168.7.12:8137`.  It has to keep running while the device
  copies.  This local cache has no signing key, so the client must be told
  not to require signatures — and the setting has to reach the daemon, so
  set it explicitly before every copy rather than relying on
  `--option require-sigs false` alone:

  ```sh
  export NIX_CONFIG='experimental-features = nix-command flakes
  substituters = http://192.168.7.12:8137 https://cache.nixos.org/
  require-sigs = false'
  ```

  No configuration in this repository sets `nix.settings.require-sigs` any
  more; the per-invocation `NIX_CONFIG` above is the supported way to scope
  the exception to the copy.
- **fastboot**: `nix shell nixpkgs#android-tools --command fastboot …`.

### Installed-system SSH and logs

The demo configuration sets `hardware.liuqin.debugTransport = "both"`.  The
deployment key is `~/.ssh/id_liuqin`; its
public half is embedded in the `openssh.authorizedKeys.keys` list of
`config/demo/configuration.nix`.  To use your own
key, generate one (`ssh-keygen -t ed25519 -f ~/.ssh/id_liuqin`) or extract
the public half of an existing private key (`ssh-keygen -y -f
~/.ssh/id_liuqin`) and replace that string.  The tablet's WLAN address comes
from DHCP, so discover it from the router or the host's neighbor table rather
than assuming the address used during bring-up.

```sh
ssh -o IdentitiesOnly=yes -i ~/.ssh/id_liuqin liuqin@<tablet-ip>

# current boot and kernel messages
journalctl -b --no-pager
journalctl -k -b --no-pager

# SSH service, including accepted and rejected login attempts
journalctl -u sshd -b --no-pager

# follow messages while reproducing a problem
journalctl -f
```

The installed system keeps a persistent journal in `/var/log/journal`, so
`journalctl --list-boots` and `journalctl -b -1` can inspect earlier boots.
`systemctl status sshd` and `systemctl status liuqin-usb-gadget` show which
debug transport is active: `"ssh"` runs `sshd` with the gadget off, `"both"`
(the demo target) runs both; the RAM installer enables its own temporary USB
root shell independently.  (The SSH path was verified on the tablet on
2026-09-29; the USB link is what the 2026-10-06 audio deploys used.)

Other operator-supplied keys: the MiPPS HMAC keys are extracted offline from
the stock `batterysecret` binary and installed root-only on the tablet —
`PORTING-NOTES.md` §2.1 (extraction) and §2.2 (installation).

When the display never comes up, work from the U-Boot/fastboot and pstore
channels instead — `PORTING-NOTES.md` §3.1 is the list.

## 2. Building
The build consumes static payloads from the separate private repository
`liuqin-firmware-assets-OS2`; no downstream release image or per-device
persist data is a build input. Authorized builders fetch the repository
through GitHub SSH, while `flake.lock` pins its exact revision and content
hash.


```sh
nix build .#uboot-bootimg --out-link result-uboot
nix build .#installer-bootimg --out-link result-installer

# the installed system plus the loader step that /boot needs
nix build .#nixosConfigurations.demo.config.system.build.toplevel
LOADER=$(nix eval --raw .#nixosConfigurations.demo.config.system.build.installBootLoader)
```

The x86_64 → aarch64 cross set (`pkgsArm`) builds the device packages once on
the host; the native aarch64 closure comes from cache.nixos.org plus those.
The flake comment explains why.

## 3. First bring-up (stock Android device)

On this device the slot state is written by
three things (`liuqin_setactive` and the boot-time claim in U-Boot, ABL's own
`set_active`), and `boot_a` is Android's.

1. **Carve the `linux` partition** out of userdata's tail, from a live
   environment (`sgdisk`/`resize.f2fs` are in the installer).  Measure the
   live geometry — the 256 GB and 512 GB SKUs differ and no constant may be
   baked in (the 512 GB example: userdata `2758144..124212216`, split at
   `45570048`, i.e. a 299.99 GiB `linux`).  A GPT backup before the write is
   mandatory.  The stock `userdata` filesystem is f2fs and cannot be shrunk
   in place, so freeing the space destroys Android's `/data`; that is a
   deliberate decision, not a command to paste.
2. **RAM-boot the installer** (path B): cold start into ABL fastboot
   (power + volume-down) and `fastboot boot result-installer/boot.img`.
3. **Push the closure and install**, from the installer's telnet shell:

   ```sh
   export PATH=/run/current-system/sw/bin:$PATH     # nixos-install needs it
   export NIX_CONFIG='experimental-features = nix-command flakes
   substituters = http://192.168.7.12:8137 https://cache.nixos.org/
   require-sigs = false'
   mount /dev/disk/by-partlabel/linux /mnt
   nix copy --from http://192.168.7.12:8137 --no-check-sigs --to /mnt <toplevel>
   nixos-install --root /mnt --no-channel-copy --no-root-passwd --system <toplevel>
   ```

   The target filesystem must carry the label the configuration expects:
   `LIUQIN_ROOT` (ext4) always, on a GPT partition labelled `linux`
   (`storage.layout = "linux-partition"`, the dual-boot/demo layout) or
   `userdata` (`whole-userdata`, the default minimal layout).  Create it with
   e.g.

   ```sh
   sgdisk --change-name=PARTNO:linux /dev/DEVICE     # renames; does not create
   mkfs.ext4 -O ^orphan_file -L LIUQIN_ROOT /dev/disk/by-partlabel/linux
   mount /dev/disk/by-partlabel/linux /mnt
   findmnt -no SOURCE,FSTYPE /mnt
   findfs LABEL=LIUQIN_ROOT
   ```

   `-O ^orphan_file` is required: e2fsprogs enables that incompat feature by
   default and this U-Boot's ext4 does not know it, which risks read errors
   on the one partition U-Boot must read.  `sgdisk --change-name` only
   renames an existing entry; creating the partition itself has no recipe in
   this repository.

   `nixos-install` writes the closure, the profile and (through
   `system.build.installBootLoader`) `/boot/extlinux/extlinux.conf` on the
   target.  It does **not** activate: the target's first-boot activation
   provisions `/etc/liuqin-nixos-root`, the marker the initrd guard verifies.

   **Alternative: nixos-anywhere.** The live environment carries
   `VARIANT_ID=installer`, and
   `lib.mkLiuqinInstallerSystem { authorizedKeys = [ ... ]; }`
   puts your key into it as root's `authorized_keys`.  nixos-anywhere then
   treats the RAM installer as a standard NixOS installer and skips kexec
   (its built-in kexec image is x86_64-only), so with step 1 done and the
   partition mounted/formatted as above:

   ```sh
   # host
   nixos-anywhere --flake .#mypad --target-host root@192.168.7.2 \
     --phases install,reboot
   ```

   The flake's configuration must already satisfy the storage guard (ext4
   label `LIUQIN_ROOT`, GPT partlabel `linux`/`userdata`, marker written at
   first boot).

4. **Put U-Boot into `boot_b`** (from ABL fastboot):
   `fastboot flash boot_b result-uboot/boot.img`.  Leave the slot attributes
   alone; the device already boots `boot_b` when B is active, and B is made
   active with `set_active` / `liuqin_setactive`.
5. Cold start → the U-Boot menu → **"Boot NixOS"**.

## 4. Updating an installed system

`nixos-rebuild` cannot rebuild on the device — no channel and no nixpkgs
source — so an update is: get the closure onto the device, set the profile,
run the loader, reboot.  Every step works
over the USB gadget link (`192.168.7.2`, `debugTransport = "usb"`/`"both"`)
or over Wi-Fi (the tablet's DHCP address).

```sh
# host: build the system and the loader script once
nix build .#nixosConfigurations.demo.config.system.build.toplevel
LOADER=$(nix eval --raw .#nixosConfigurations.demo.config.system.build.installBootLoader)
```

### a. Binary cache (small HTTP server)

```sh
# host: fill the cache and serve it on an address the tablet can reach
# (192.168.7.12 is the USB link; use the LAN address for Wi-Fi)
nix copy --to file:///var/tmp/liuqin-cache "$(readlink -f result)" "$LOADER"
(cd /var/tmp/liuqin-cache && python3 -m http.server 8137 --bind 192.168.7.12)
```

```sh
# device (telnet 2323 or SSH): fetch from the cache
N=/run/current-system/sw/bin
export NIX_CONFIG='experimental-features = nix-command flakes
substituters = http://192.168.7.12:8137 https://cache.nixos.org/
require-sigs = false'
$N/nix copy --from http://192.168.7.12:8137 --no-check-sigs <toplevel> <loader>
```

### b. Delta import over SSH (no cache server)

Only the paths the device is missing are exported on the host and imported as
root on the device.  Measured 2026-10-06: 360 MB in ~10 s over the USB link.

```sh
# host
comm -13 \
  <(ssh liuqin@192.168.7.2 'nix-store -qR /run/current-system' | sort -u) \
  <(nix-store -qR "$(readlink -f result)" "$LOADER" | sort -u) \
  > /var/tmp/liuqin-delta.txt
nix-store --export $(cat /var/tmp/liuqin-delta.txt) > /var/tmp/liuqin-delta.nar
scp /var/tmp/liuqin-delta.nar liuqin@192.168.7.2:/var/tmp/
```

```sh
# device, as root (the USB telnet shell, or `sudo sh -c`)
nix-store --import < /var/tmp/liuqin-delta.nar
```

### c. Activate (either transport)

```sh
# device (telnet 2323 or SSH)
N=/run/current-system/sw/bin
$N/nix-env --profile /nix/var/nix/profiles/system --set <toplevel>
<loader> <toplevel>          # copy kernel/initrd/dtb into /boot, rewrite extlinux.conf
<toplevel>/bin/switch-to-configuration boot
systemctl reboot
```

Order matters: the profile first, then the loader script
(`extlinux-conf-builder.sh -g 8 ...` keeps eight generations and needs the
new profile link to see them).  `switch-to-configuration` does **not** touch
the bootloader — the loader script above is a separate step.  Rollback is the
U-Boot menu's "NixOS Generations" entry.

If the new kernel changes USB behaviour, reboot rather than
`switch-to-configuration switch`.

## 5. Reinstalling

Same as §3 steps 2–3 (RAM installer + `nixos-install` over the network); a
reinstall onto the existing `linux` partition keeps the marker and needs no
partitioning.  Do not touch GPT or slot attributes for a reinstall.

## 6. Booting, switching, recovering

- **U-Boot menu**: `Boot Android` (a real slot *selection*: GPT attributes,
  type-GUID roles and UFS `bBootLunEn`, then reset), `Boot NixOS`,
  `NixOS Generations` (rollback), `Enable Fastboot Mode`, `Reset Device`,
  `Power Off`, `Reboot to ABL`, plus two read-only diagnostics (GPT probe,
  ABL log scan).  The menu counts down 5 s to the first entry, `Boot NixOS`;
  any button press stops the countdown.
- **Entering ABL fastboot**: cold start with **power + volume-down**.  Coming
  from the menu's `Reboot to ABL` also lands in ABL, but with the restart
  reason set to bootloader, and then `fastboot boot` is refused
  (`Device Error`) while `fastboot flash` still works — use the cold start
  for RAM boots.
- **Reboot** from a running system: `systemctl reboot`.
- To return to U-Boot automatically on the next normal reboot after Android
  finishes booting, install the [KernelSU module](../pkgs/ksu-return-to-uboot/README.md)
  on Android. It selects B through Android's Boot Control HAL, which must
  update the GPT type-GUID roles and UFS boot LUN along with the slot attributes.
  The module checks `boot_b`'s Android image magic and liuqin U-Boot log
  prefix before switching.
- Manual return from Android: `adb reboot bootloader` → ABL's fastboot →
  `fastboot reboot`.  The stock fastboot client refuses `set_active` there
  (`Device does not support slots`: its `has-slot` probe fails against this
  ABL's narrow getvar surface), so send the raw command (`set_active:b`) —
  or do it from U-Boot's own fastboot (menu's `Enable Fastboot Mode`), where
  `fastboot set_active b` works.  Either way ABL clears the target's
  *successful* flag and refills its seven retries; U-Boot re-claims the slot
  it was handed on every boot (`liuqin_slot_autoclaim`, `liuqin_ab_mark=0`
  disables it), so the retry budget no longer drains across reboots.
- If the installed system cannot bring up Wi-Fi and the USB gadget does not
  come up, the gadget unit already retries on its own (5 s apart, no start
  limit); check `systemctl status liuqin-usb-gadget` and
  `dmesg | grep 'soft reset failed'` (that dump is what named the installer's
  dead USB channel, `PORTING-NOTES.md` §1) before falling back to the RAM
  installer.

## 7. Fingerprint (FPC1264)

The sensor sits in the power button and the vendor trustlet does the matching;
Linux drives power/reset/IRQ and the QSEECOM TEE transport. fprintd alone owns
the published prints. A per-account canonical `.gallery` stores one opaque
database with up to five finger/template-ID pairs; existing single-finger
prints remain readable until the first successful gallery enrolment. Static
`fpcliu.mdt` and its segments come from the OS2.0.4 asset repository;
Gatekeeper/RPMB state is per-device.

### What is verified, what is not

- Previously verified (2026-10-06): Settings enrolment, `gdm-fingerprint`
  unlock and adaptive template updates with the prior firmware. This is not
  evidence for the OS2.0.4 firmware or the redesigned enrolment transaction.
- On OS2.0.4 (2026-10-30/31), a new Linux Gatekeeper credential passed
  signed preflight. The first physical attempt failed at `sample` with no
  accepted export or print; its uncertain marker was retained for audit.
  The new TOD had imposed an exact `remaining=19..0` sequence that the
  working native client never required and had obscured its own protocol
  errors. After removing that assumption, `seeker` enrolled a
  `right-index-finger` through fprintd; `fprintd-list` found it and
  `fprintd-verify` returned `verify-match`. A later switch to the known-good
  build also returned `verify-match` for that print.
- The operator reported intermittent unresponsive presses during enrolment.
  Kernel `fpc1020_poll()` consumes pending IRQs; the OEM client's post-arm
  drain may drop an early real press. Removing it experimentally caused
  sensor-setup IRQs to be captured instead, and verification returned
  `verify-unknown-error`; that unsafe change was reverted. Captures rejected
  by known positive TA statuses were also being misclassified because their
  diagnostic is on stderr, not stdout. The classification fix still needs
  hardware validation; the early-press UX limitation remains open.
- In a root-private OS2 lab, the original one-template database and a new
  two-template export had distinct stable IDs. Selective TA deletion produced
  a new-only database; the new finger matched it and the old finger did not.
  On 2026-10-31, a separate production `right-thumb` enrolment completed:
  `fprintd-list seeker` showed both `right-thumb` and `right-index-finger`,
  each returned `verify-match` on the combined gallery, and deliberately
  pressing the index finger for `right-thumb` returned `verify-no-match`.
  fprintd exited and restarted between checks; the canonical `.gallery` was
  root-owned mode 0600, no pending export remained, and the old single-finger
  file was preserved. Production deletion and cold-boot recovery remain open.
- The multi-finger publisher refuses ambiguous exports rather than guessing
  an ID. Fingerprint authentication for `su`/SSH is not enabled.

### Static firmware and account credential

The static `fpcliu.mdt` and `b00`-`b08` files are packaged from
`liuqin-firmware-assets-OS2`; the enabled module installs that immutable
package and points the OEM runtime at it. No firmware files need to be copied
onto the device. The asset repository contains proprietary payloads extracted
from official OS2.0.4 images, not per-device credentials, Gatekeeper state or
RPMB data.

NixOS compresses its normal firmware projection to `*.zst`. The shared
read-only `/run/firmware` mount therefore layers the immutable, uncompressed
FPC package ahead of that projection; both `fpcliu.mdt` and `fpcliu.b00`
must exist there. If either is missing, the OEM runtime stops before touching
the trustlet or changing account metadata. Rebuilding only the Python client
does not repair a running system's existing firmware mount.

- **Account credential (once per account).** `sudo liuqin-fpc-credential
  --create <user>`: root, a local terminal (not SSH), and it authenticates the
  account password through its own PAM service. It creates the Gatekeeper
  credential and the authenticated RPMB state under
  `/var/lib/liuqin-fingerprint/native/`. Run it once and never repeat it (the
  tool refuses to re-create an existing identity).

An explicit reset of an abandoned Linux fingerprint identity abandons its
old SID and makes its previously enrolled prints unusable. Remove only the
verified account's root-private native state and stale fprintd prints, then
run `sudo liuqin-fpc-credential --create <user>` from a local terminal.
Deleting host files does **not** erase the corresponding Gatekeeper/RPMB
record, so a rejected new credential must not be silently retried or bypassed.
Never delete Android's credential state.

### Enrol and use

1. Check private account metadata without invoking the TEE:
   `sudo liuqin-fpc-credential --status <user>`. `account_mismatch` means the
   stored username and the current account name differ even if the UID is
   unchanged; do not hand-edit metadata or claim the old SID for a new print.
   `missing_handle` needs explicit first-time provisioning.
   `prepared_input_unexpired` only means its *metadata* has not expired; it
   does not prove the boot-local key is still present.
2. Settings -> System -> Users -> pick the account -> **Fingerprint Login** ->
   **Add**. A password PAM/polkit prompt can prepare the one-use trustlet input;
   if it is absent (for example, an autologin session), run
   `sudo liuqin-fpc-credential --prepare-acceptance <user>` from a local
   terminal first. Press the sensor repeatedly, lifting between presses.
   Accepted samples, capture retries and lift prompts are distinct progress
   events. A failed or cancelled operation is not a successful enrolment.
3. fprintd publishes `/var/lib/fprint/<user>/fpc1264_oem/liuqin-fpc1264-oem/.gallery`.
   The old per-finger file stays unchanged after migration but is no longer
   authoritative. A root-private accepted database **and** ID inventory
   survive a daemon crash before publication; an ambiguous TA/export result
   is blocked from automatic retry. Check
   `/var/lib/liuqin-fingerprint/pending/` and the failure code before manual
   recovery; never delete an uncertainty marker blindly.
4. Check `fprintd-list <user>` for both finger labels, verify each enrolled
   finger separately (`fprintd-verify -f <finger> <user>`), then test screen
   unlock. An unrelated finger must mismatch. Deleting a mapped finger uses
   the TA's selective deletion and republishes the gallery atomically; a
   failed deletion must not remove the surviving finger.

Command-line path (the same fprintd publisher as Settings):

```sh
sudo liuqin-fpc-enrol --enrol <user> <finger>          # prepares input, then fprintd
sudo liuqin-fpc-enrol --enrol-prepared <user> <finger> # use existing one-use input
fprintd-verify <user>                                 # in a session terminal
sudo liuqin-fpc-credential --sync-password <user>     # after a password change
```

If `--status <user>` reports `prepared_input_unexpired`, the metadata exists
but the kernel key still needs validation at consumption: use
`--enrol-prepared`, not `--enrol` (which attempts a second preparation).
If it reports `export_uncertain`, **stop**; a root-private marker may reflect
TEE changes that cannot be inferred from the absence of a saved print.

### Testing the kernel side without the daemon

The first check after a kernel change; it exercises the modules, the device
nodes and the trustlet on their own:

```sh
modprobe qseecomtee fpc1020
ls -l /dev/fpc1020 /dev/tee0 /dev/teepriv0 /dev/bsg/0:0:0:49476
liuqin-fpc-oem-runtime --ufs-rpmb-read-only --hw-auth-probe
```

The last command uses the packaged firmware to load `fpcliu` into the TEE and
reports the RPMB metadata.

### Deploying an update

A fingerprint change is an ordinary system-closure update: build on the host and
copy the closure over (section 4 - the HTTP cache or the SSH delta import, over
USB at 192.168.7.2 or the tablet's Wi-Fi address).  `/var/lib/liuqin-fingerprint`
(the credential) and `/var/lib/fprint` (the templates) live in `/var` and
survive updates and reboots; a reinstall that keeps the `linux` partition keeps
them too.

### Debugging

- `sudo liuqin-fpc-credential --status <user>` separates account mismatch,
  missing handle, expired preparation and accepted-but-unpublished export
  without reading a key or touching the trustlet.
- Enrolment emits allowlisted `fpc_event=1 kind=ready|sample|retry|lift|finalizing|recovered|committed|phase|ta_reject`
  events internally; the TOD driver maps them to fprintd progress and retry
  notifications. `fpc_error=account_mismatch|prepared_input_missing|prepared_input_expired|busy|export_uncertain|runtime_failure|storage_failure`
  distinguishes recovery actions without logging passwords, HATs or templates.
  `phase=sample` identifies the last native command, **not** necessarily its
  failure: a protocol error may have stopped the child. The driver's own
  protocol error is now preserved; only a validated negative TA response is
  reported as `ta_status=<number>`.
- `journalctl -b` shows OEM enrol/verify failures; `busctl monitor --system
  net.reactivated.Fprint` shows D-Bus `EnrollStatus`/`VerifyStatus`. A desktop
  progress callback is not proof of disk persistence: fprintd reports success
  only after its print file has been saved and synced. A failed pending-export
  acknowledgement is retried when the stored print is loaded.

## 8. Traps (all measured)

- The telnet shell is busybox.  On images before the `pkgs/usb-login.nix`
  PATH fix, `reboot` selects the busybox applet (no-op, exit 0), while
  `dmesg`, `nix` and `journalctl` need `/run/current-system/sw/bin` on PATH.
  Use `systemctl reboot` on either version.
- The installed system's nix has the new CLI disabled: pass
  `--extra-experimental-features "nix-command"` to `nix copy`.
- `nixos-install` needs `nix-env` on PATH (same PATH issue).
- U-Boot's fastboot wedges on ~192 MiB images; large images go through ABL's
  fastboot (`fastboot boot`/`flash`).
- Never leave a self-built image on `boot_a`, and never leave the slot state
  half-switched.  The installer path never writes GPT or slot attributes.
- The RAM installer is the only installation interface; the former
  host-side fastboot installer and prebuilt rootfs-image path have been
  removed.

## 9. Camera

The camera stack is off unless the configuration enables
`hardware.liuqin.camera.enable`; `README.md` describes the option set and the
sub-switch, and `PORTING-NOTES.md` (Camera) plus
`docs/TODO/CAMERA-MAINLINE.md` carry the hardware facts and open items.  The
installed demo configuration enables it.

The three sensors share one CSID, so exactly one camera can be streamed at a
time, and nothing routes at boot.  libcamera's simple pipeline routes the
graph itself; for a raw capture, a link reset or manual focus:

```sh
cam --stream role=raw --capture=5 --file=/tmp/frame.raw  # routes the graph itself
media-ctl -r -d /dev/media0                           # reset all links
v4l2-ctl -d "$(media-ctl -p -d /dev/media0 | grep -A3 dw9768 | grep -o '/dev/v4l-subdev[0-9]*' | head -1)" \
  --set-ctrl focus_absolute=536                       # focus while streaming
```

The sensor module is blacklisted from udev autoload and loaded late by the
`liuqin-camera-probe` oneshot, which retries three times 5 s apart.  If it
still fails, `systemctl status liuqin-camera-probe` shows the failed unit and
every camera stays absent until a later success or a reboot — there is no
second probe, and the panel is the only console.

Only one consumer can hold the camera, and wireplumber's v4l2 monitor counts
as one.  In a GNOME session mask wireplumber for the duration of a raw
capture:

```sh
systemctl --user mask --now wireplumber
# ... capture ...
systemctl --user unmask --now wireplumber
```

The desktop user must be in the `video` group; the camera module grants that
group the dma-buf heaps libcamera's software ISP opens.  Finally, the `cam`
found on `PATH` is the stock libcamera — the autofocus-patched build is
injected only into pipewire/wireplumber (`cam-af` runs it from the command
line) — so a plain `cam` capture verifies the stock path, not the AF path.

## 10. Where to look when something is wrong

| symptom | first stop |
| --- | --- |
| no boot output at all | panel photo, then U-Boot `fastboot getvar stage*` / `con*` (`PORTING-NOTES.md` §3.1) |
| kernel panic / lockup | ramoops pstore + persistent journal (`journalctl -b -1`) |
| display dark under U-Boot | patch 0003 retry cycle (`PORTING-NOTES.md` §1) |
| no USB debug channel | `systemctl status liuqin-usb-gadget` (it retries by itself), `dmesg` for `soft reset failed`, or the RAM installer (`PORTING-NOTES.md` §1) |
| USB-C role/DP/charging | `PORTING-NOTES.md` §1 (Type-C, DP Alt Mode, MiPPS) and §2 for MiPPS keys |
| camera missing | `systemctl status liuqin-camera-probe`, then `media-ctl -r` |
