# Installing, updating and operating a liuqin system

Operational companion to `PORTING-NOTES.md` (why the port looks the way it
does) and `BOOT-ARCHITECTURE.md` (the boot chain in detail).  Everything below
was exercised on the unit.

## 0. The two ways this board boots an OS

|  | **A. U-Boot** (the installed system's normal path) | **B. ABL direct** |
|---|---|---|
| chain | ABL → `boot_b` (U-Boot) → menu → `sysboot`/extlinux → kernel | ABL → `fastboot boot <boot.img>` → kernel |
| display | ABL keeps the display running for the menu, so the kernel inherits a *running* pipeline; patch 0015 retries the cycle at 6, 10, 14, 18 and 22 s, with the panel measured to light between ~10 and 20 s | ABL finds no `/reserved-memory/splash_region` in the boot.img's DT and calls `DisableDisplay()`; the first modeset lights the panel cleanly (~1.9 s) |
| generation selection | yes — the menu lists them | no — one image, one generation |
| used for | daily boots | RAM installer, tests, recovery |

Path A is the product.  Path B is what makes the installer and any
`fastboot boot` test image look good: the flake's kernel DT renames the node to
`linux_splash@b8000000` (patch 0001) exactly so ABL takes its teardown branch.
Making path A as clean as B is the "display-pipeline stop at probe" TODO in
`PORTING-NOTES.md` (Display).

## 1. Host side

- **USB network.**  The tablet is `192.168.7.2/24`; the host is
  `192.168.7.19/24` on the NCM interface (check with `ip -4 addr show`).  An
  installed system presents that channel when `hardware.liuqin.usbShell` is
  enabled; the example configuration selects SSH over WLAN instead, so take it
  with `hardware.liuqin.debugTransport = "usb"`, or keep both with `"both"`.
  It is the same arrangement the RAM installer brings up from its own units
  (`config/installer.nix`), not from this module: DHCP server plus a **busybox
  telnet root shell on port 2323**.  If the USB channel is selected and nothing
  answers, check the cable first — `enp14s0u3` simply disappears when it is
  unplugged.
- **Installed-system debug transport.**  `hardware.liuqin.debugTransport`
  accepts `"ssh"` (default), `"usb"`, `"both"`, or `"none"`.  The selector
  enables or disables the installed system's OpenSSH service and legacy USB
  gadget using `mkDefault`, so an explicit `services.openssh.enable` or
  `hardware.liuqin.usbShell.enable` can still override it.  While SSH is on it
  also defaults `PasswordAuthentication` off, so the path is key-only unless
  the machine configuration overrides that; enroll an authorized key before
  relying on it.
- **Binary cache for pushes.**  A plain `python3 -m http.server 8137 --bind
  192.168.7.19` serving `/var/tmp/liuqin-cache` (`hub` process name
  `liuqincache`).  Fill it on the host with `nix copy --to
  file:///var/tmp/liuqin-cache <store paths>`; the device then copies from
  `http://192.168.7.19:8137`.  It has to keep running while the device copies.
- **fastboot**: `nix shell nixpkgs#android-tools --command fastboot …`.

### Installed-system SSH and logs

The installed example configuration uses `hardware.liuqin.debugTransport =
"ssh"`.  The deployment key is `~/.ssh/id_liuqin`; the matching public key is
declared in the example configuration.  The tablet's WLAN address comes from
DHCP, so discover it from the router or the host's neighbor table rather than
assuming the address used during bring-up.

```sh
ssh -o IdentitiesOnly=yes -i ~/.ssh/id_liuqin demo@<tablet-ip>

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
debug transport is active.  The intended installed state is `sshd=active` and
`liuqin-usb-gadget=inactive`; the RAM installer still enables its temporary
USB root shell independently.

This SSH path was verified on the tablet on 2026-09-29 after installing
system generation `is649gr0212v117j8z1b5s13x28mxf8s`.  The journal recorded
the SSH daemon startup and successful public-key logins with the `liuqin` key.

## 2. Building

```sh
nix build .#uboot-bootimg        # U-Boot boot.img, the payload of boot_b
nix build .#installer-bootimg    # RAM installer, ABL-bootable only

# the installed system plus the loader step that /boot needs
nix build .#nixosConfigurations.demo.config.system.build.toplevel
LOADER=$(nix eval --raw .#nixosConfigurations.demo.config.system.build.installBootLoader)
```

The x86_64 → aarch64 cross set (`pkgsArm`) builds the device packages once on
the host; the native aarch64 closure comes from cache.nixos.org plus those.  The
flake comment explains why.

## 3. First bring-up (stock Android device)

Preconditions and rules first: read the workspace `AGENTS.md` §7 and the
dualboot `docs/SLOT-SWITCH.md`.  On this device the slot state is written by
three things (`liuqin_setactive` and the boot-time claim in U-Boot, ABL's own
`set_active`), and `boot_a` is Android's.

1. **Carve the `linux` partition** out of userdata's tail, from a live
   environment (`sgdisk`/`resize.f2fs` are in the installer).  Measure the live
   geometry — the 256 GB and 512 GB SKUs differ and no constant may be baked
   in (the 512 GB example: userdata `2758144..124212216`, split at
   `45570048`, i.e. a 299.99 GiB `linux`).  A GPT backup before the write is
   mandatory.
2. **RAM-boot the installer** (path B): cold start into ABL fastboot
   (power + volume-down) and `fastboot boot result-installer/boot.img`.
3. **Push the closure and install**, from the installer's telnet shell:

   ```sh
   export PATH=/run/current-system/sw/bin:$PATH     # nixos-install needs it
   mount /dev/disk/by-partlabel/linux /mnt
   nix --extra-experimental-features "nix-command" copy \
       --from http://192.168.7.19:8137 --no-check-sigs --to /mnt <toplevel>
   nixos-install --root /mnt --no-channel-copy --no-root-passwd --system <toplevel>
   ```

   `nixos-install` writes the closure, the profile and (through
   `system.build.installBootLoader`) `/boot/extlinux/extlinux.conf` on the
   target.  It does **not** activate: the target's first-boot activation
   provisions `/etc/liuqin-nixos-root`, the marker the initrd guard verifies.
4. **Put U-Boot into `boot_b`** (from ABL fastboot):
   `fastboot flash boot_b result-uboot/boot.img`.  Leave the slot attributes
   alone; the device already boots `boot_b` when B is active, and the dualboot
   docs describe how B is made active (`set_active` / `liuqin_setactive`).
5. Cold start → the U-Boot menu → **"Boot NixOS"**.

## 4. Updating an installed system (no installer, no nixos-rebuild)

Measured 2026-09-28.  `nixos-rebuild` does not exist on the device
(`config/installer.nix` disables it, and the installed system has no channel);
the update is three commands plus a reboot.

```sh
# host
nix build .#nixosConfigurations.demo.config.system.build.toplevel
LOADER=$(nix eval --raw .#nixosConfigurations.demo.config.system.build.installBootLoader)
nix copy --to file:///var/tmp/liuqin-cache "$(readlink -f result)" "$LOADER"

# device (telnet 2323)
N=/run/current-system/sw/bin
$N/nix --extra-experimental-features "nix-command" copy \
    --from http://192.168.7.19:8137 --no-check-sigs <toplevel> <loader>
$N/nix-env --profile /nix/var/nix/profiles/system --set <toplevel>
<loader> <toplevel>          # copy kernel/initrd/dtb into /boot, rewrite extlinux.conf
<toplevel>/bin/switch-to-configuration boot
systemctl reboot
```

Order matters: the profile first, then the loader script (`extlinux-conf-
builder.sh -g 8 ...` keeps eight generations and needs the new profile link to
see them).  `switch-to-configuration` does **not** touch the bootloader — the
loader script above is a separate step.  Rollback is the U-Boot menu's
"NixOS Generations" entry.

## 5. Reinstalling

Same as §3 steps 2–3 (RAM installer + `nixos-install` over the network); a
reinstall onto the existing `linux` partition keeps the marker and needs no
partitioning.  Do not touch GPT or slot attributes for a reinstall.

## 6. Booting, switching, recovering

- **U-Boot menu**: `Boot Android` (a real slot *selection*: GPT attributes,
  type-GUID roles and UFS `bBootLunEn`, then reset), `Boot NixOS`,
  `NixOS Generations` (rollback), `Enable Fastboot Mode`, `Reset Device`,
  `Power Off`, `Reboot to ABL`, plus two read-only
  diagnostics (GPT probe, ABL log scan). The menu counts down 5 s to the first
  entry, `Boot NixOS`; any button press stops the countdown.
- **Entering ABL fastboot**: cold start with **power + volume-down**.  Coming
  from the menu's `Reboot to ABL` also lands in ABL, but with the restart
  reason set to bootloader, and then `fastboot boot` is refused
  (`Device Error`) while `fastboot flash` still works — use the cold start for
  RAM boots.
- **Reboot** from a running system: `systemctl reboot`. Older images put
  busybox first on the telnet shell's PATH; their `reboot` applet returns 0
  under systemd without restarting the device.
- Coming back from Android: `adb reboot bootloader` → ABL's fastboot
  (`set_active b`) → `fastboot reboot`; U-Boot's own fastboot (menu's
  `Enable Fastboot Mode`) accepts `set_active b` too.  Either way ABL clears
  the target's *successful* flag and refills its seven retries; U-Boot
  re-claims the slot it was handed on every boot (`liuqin_slot_autoclaim`,
  `liuqin_ab_mark=0` disables it), so the retry budget no longer drains
  across reboots.

## 7. Traps (all measured)

- The telnet shell is busybox. On images before the `pkgs/usb-login.nix`
  PATH fix, `reboot` selects the busybox applet (no-op, exit 0), while
  `dmesg`, `nix` and `journalctl` need `/run/current-system/sw/bin` on PATH.
  Use `systemctl reboot` on either version.
- The installed system's nix has the new CLI disabled: pass
  `--extra-experimental-features "nix-command"` to `nix copy`.
- `nixos-install` needs `nix-env` on PATH (same PATH issue).
- U-Boot's fastboot wedges on ~192 MiB images; large images go through ABL's
  fastboot (`fastboot boot`/`flash`).
- Never leave a self-built image on `boot_a`, and never leave the slot state
  half-switched: the dualboot `docs/SLOT-SWITCH.md` is the authority on both.
  The installer path never writes GPT or slot attributes.
