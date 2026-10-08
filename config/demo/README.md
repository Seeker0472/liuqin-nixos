# liuqin demo machine configuration

Machine flake for the Xiaomi Pad 6 Pro (liuqin, SM8475), built as a consumer of
the BSP [liuqin-nixos](https://github.com/Seeker0472/liuqin-nixos): the BSP is
the hardware-support layer (kernel, firmware wiring, device packages, the NixOS
module, image assembly) and deliberately carries no site configuration; this
directory is the other half. `nix flake init -t
github:Seeker0472/liuqin-nixos` produces exactly these files.

## Before building

`configuration.nix` is the file to edit. At minimum:

- the user: `users.users.liuqin` (name, `initialPassword`, your SSH public key);
  `services.displayManager.autoLogin.user` and `nix.settings.trusted-users`
  all name the same account;
- `networking.hostName` and `time.timeZone`;
- the sensor stack: `hardware.liuqin.sensors.sscConfigHash` carries the demo
  unit's archive hash. A different unit must register its own archive and
  re-derive the hash, or drop the line to leave the SSC stack out (the module
  warns).

Comments refer to paths in the BSP repository (`docs/…`, `pkgs/…`); the BSP's
`README.md` is the reference for what the hardware does and does not support.

## Operator-supplied payloads

No proprietary data is in either repository. A build that carries firmware
needs these archives on the build host, registered as fixed-output store
paths; the filename must match, because the store path's name is what
`requireFile` looks up:

- `liuqin-firmware-vpu.tar.zst`, `liuqin-firmware-cs35l41.tar.zst` — the VPU
  and speaker-amplifier firmware;
- `boot.img` — the downstream release image carrying the bulk firmware tree;
- `liuqin-ssc-config.tar.zst` — the sensor configuration set (only when
  `sscConfigHash` is set);
- `stock-base-dtbs.tar.zst`, `stock-dtbo-entries.tar.zst` — the stock DT
  archives used by the boot.img pipeline.

```sh
nix-store --add-fixed sha256 <file>   # once per archive, per build host
```

`hardware.liuqin.firmware.{vpu,cs35l41,bootImg}` can also take plain paths
(`./liuqin-firmware-vpu.tar.zst`) instead of the store registration. The BSP's
`README.md`, `docs/PORTING-NOTES.md` and `.gitignore` describe how to extract
each archive.

## Build and install

```sh
nix build .#installer-bootimg   # RAM installer; the only first-install path
nix build .#bootimg             # bootable image for the U-Boot/ABL path
nix build .#uboot-bootimg       # the U-Boot boot.img
```

The install and update flow — fastboot-booting the RAM installer, the telnet
or nixos-anywhere path, and the U-Boot generation menu — is
[docs/INSTALL.md](https://github.com/Seeker0472/liuqin-nixos/blob/main/docs/INSTALL.md)
in the BSP.

## Updating

`nix flake update` advances the `liuqin` input to the newest BSP `main`; the
nixpkgs pin follows the BSP's own lockfile, so the combination stays the one
the BSP was validated against. Pin the input to a revision for
reproducibility:

```nix
inputs.liuqin.url = "github:Seeker0472/liuqin-nixos/<rev>";
```

Do not add a `nixpkgs` input, or make `liuqin` follow one: the BSP is tested
against its own nixpkgs pin only.
