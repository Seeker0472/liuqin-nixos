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
- the sensor stack uses the static OS2.0.4 configuration from the asset
  repository; its registry is still provisioned from this unit's private
  persist partition. WLAN/BT identities, speaker calibration, MiPPS keys and
  fingerprint credentials/RPMB state remain device-local.

Comments refer to paths in the BSP repository (`docs/…`, `pkgs/…`); the BSP's
`README.md` is the reference for what the hardware does and does not support.

## Asset repository

Builds require GitHub SSH access to the private
`liuqin-firmware-assets-OS2` repository. The consumer's lock file pins its
revision and content hash; no sibling checkout or `--override-input` is
required. The nested
`inputs.liuqin.inputs.firmwareAssets.follows = "firmwareAssets"` wiring makes
the BSP and consumer use the same assets.

The asset repository contains proprietary static payloads extracted from
official OS2.0.4 images, pinned upstream firmware and generated AudioReach
topology, with source/output hashes and provenance. Do not publish or
redistribute it without authorization. The build does not use the downstream
release boot image or per-host `requireFile` registrations.

Per-device persist contents, credentials, calibration, identities, sensor
registry, MiPPS keys and RPMB state are not stored in the asset repository.

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
nixpkgs pin follows the BSP's own lockfile. The private asset input remains
independently pinned to its Git revision and content hash. Pin the BSP input to
a revision for reproducibility:

```nix
inputs.liuqin.url = "github:Seeker0472/liuqin-nixos/<rev>";
```

Do not add a `nixpkgs` input, or make `liuqin` follow one: the BSP is tested
against its own nixpkgs pin only.
