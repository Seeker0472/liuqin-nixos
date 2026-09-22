# SPDX-License-Identifier: MIT
#
# NixOS live installer for the Xiaomi Pad 6 Pro. This configuration is
# intentionally separate from the installed desktop configuration: it boots
# from a tmpfs/overlay root, so it must not run the persistent-root guard or
# any service that reads device-private state from persist.
{ config, lib, modulesPath, pkgs, ... }:

let
  # NetworkManager's nixpkgs build enables ModemManager unconditionally. The
  # tablet has no cellular modem, so keep NetworkManager's Wi-Fi/NCM support
  # while removing that unrelated runtime dependency from the live closure.
  networkmanager = pkgs.networkmanager.overrideAttrs (old: {
    mesonFlags = map (
      flag:
      if flag == "-Dmodem_manager=true" then "-Dmodem_manager=false" else flag
    ) old.mesonFlags;
    buildInputs = lib.filter (
      input: lib.getName input != "modemmanager"
    ) old.buildInputs;
  });

  installNixos = pkgs.writeShellApplication {
    name = "liuqin-install-nixos";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      nixos-install
      util-linux
    ];
    text = ''
      set -eu

      usage() {
        cat >&2 <<'EOF'
      Usage:
        liuqin-install-nixos --flake FLAKE [nixos-install options]
        liuqin-install-nixos [nixos-install options]

      Before running this command, partition and format the target, mount its
      root filesystem at /mnt, and put the target configuration under
      /mnt/etc/nixos or provide --flake. This helper never partitions or
      formats a device on its own.
      EOF
      }

      if [ ! -d /mnt ] || ! findmnt --mountpoint /mnt >/dev/null 2>&1; then
        echo "liuqin-install-nixos: mount the target root filesystem at /mnt first" >&2
        exit 2
      fi

      if [ "$#" -eq 0 ] && [ ! -f /mnt/etc/nixos/configuration.nix ]; then
        usage
        exit 2
      fi

      nixos-install --root /mnt --no-channel-copy "$@"

      # The initrd storage guard runs before the target root is mounted and
      # therefore cannot rely on tmpfiles/activation from the first boot.  A
      # nixos-install invocation does not boot the target, so install the
      # guard marker explicitly while /mnt is still mounted.
      printf 'LIUQIN_NIXOS_ROOT_V1\n' > /mnt/etc/liuqin-nixos-root
      chmod 0644 /mnt/etc/liuqin-nixos-root
      chown root:root /mnt/etc/liuqin-nixos-root
    '';
  };
in
{
  imports = [
    "${modulesPath}/installer/netboot/netboot.nix"
    "${modulesPath}/profiles/perlless.nix"
  ];

  # The installer deliberately uses its own kernel variant. It keeps the
  # validated display hand-off/earlycon behaviour, but promotes the USB/input
  # path to built-in so a RAM-only image never depends on a module tree.
  boot.kernelPackages = pkgs.linuxPackagesFor pkgs.liuqinInstallerKernel;
  # The generic NixOS default list contains PC storage modules such as
  # ata_piix. This kernel is intentionally device-specific and does not ship
  # those modules; the live root only needs the filesystems used to mount its
  # own squashfs/overlay and the target filesystem later in stage 2.
  boot.initrd.includeDefaultModules = false;
  boot.initrd.availableKernelModules = lib.mkForce [
    "squashfs"
    "overlay"
    "loop"
  ];
  boot.initrd.kernelModules = lib.mkForce [
    "loop"
    "overlay"
  ];
  boot.swraid.enable = lib.mkForce false;
  boot.initrd.systemd.enable = true;
  system.nixos-init.enable = lib.mkForce false;
  # The standard installation-device profile enables every supported storage
  # controller and a large set of repair tooling. This tablet has a fixed UFS
  # topology and the kernel already has the required UFS driver built in.
  hardware.enableAllHardware = lib.mkForce false;
  boot.kernelParams = [
    "qcom_q6v5_pas.slpi_auto_boot=0"
    "rootwait"
    # Match the downstream 6.17 installer/native image: only stop fbcon from
    # taking over ABL's simplefb. Do not disable SMMU or display clocks here;
    # the live image needs IOMMU-backed UFS/PCIe (Wi-Fi) as well.
    "initcall_blacklist=simplefb_driver_init"
    "earlycon=simplefb"
    "console=drm_log"
    "console=tty0"
    "firmware_class.path=/var/lib/firmware:${pkgs.liuqinInitrdFirmware}/lib/firmware"
  ];

  # WLAN firmware is needed before the netboot system has switched to its
  # squashfs-backed root. Keep the installer device-specific:
  # enabling the generic redistributable firmware bundle would add hundreds of
  # megabytes of unrelated linux-firmware to the live root.
  hardware.enableRedistributableFirmware = lib.mkForce false;
  hardware.firmware = [ pkgs.liuqinInitrdFirmware ];
  # Keep the full device firmware out of this RAM-only installer. The live
  # environment only needs WLAN firmware to reach the network; the installed
  # system carries its complete firmware policy separately.
  boot.initrd.systemd.contents."/var/lib/firmware".source =
    "${pkgs.liuqinInitrdFirmware}/lib/firmware";

  networking.hostName = "liuqin-installer";
  networking.networkmanager.enable = true;
  networking.networkmanager.package = networkmanager;
  # NetworkManager owns both association and per-connection DHCP.  Do not
  # start the separate dhcpcd service as well: it is redundant here and makes
  # the live image larger and can race NetworkManager for the same interface.
  networking.useDHCP = lib.mkForce false;
  networking.firewall.enable = false;
  # NetworkManager enables these by default, but the installer has no modem.
  networking.modemmanager.enable = lib.mkForce false;
  security.polkit.enable = lib.mkForce false;
  security.sudo.enable = lib.mkForce false;
  services.logrotate.enable = lib.mkForce false;
  services.nscd.enable = lib.mkForce false;
  systemd.oomd.enable = lib.mkForce false;
  # No NSS plugin modules are needed in the live environment; glibc's built-in
  # files/dns lookup remains available and this also avoids the nscd assertion.
  system.nssModules = lib.mkForce [ ];
  # The normal NixOS default profile adds Perl, rsync, and strace. None is
  # needed to boot this installer or run nixos-install, and Perl alone is a
  # large fraction of the compressed live-store closure.
  environment.defaultPackages = lib.mkForce [ ];

  # Keep the system-provided installer helpers disabled: the custom wrapper
  # above is the only installer command needed in the live closure, and both
  # nixos-install and nixos-generate-config otherwise add unwanted tooling.
  system.tools = {
    nixos-build-vms.enable = false;
    nixos-enter.enable = false;
    nixos-generate-config.enable = false;
    nixos-install.enable = false;
    nixos-option.enable = false;
    nixos-rebuild.enable = false;
    nixos-version.enable = false;
  };

  # The tablet has no room for the full installation-media documentation
  # closure, and the installer remains usable from the console or SSH.
  documentation.enable = lib.mkForce false;
  documentation.nixos.enable = lib.mkForce false;
  documentation.man.enable = lib.mkForce false;
  documentation.info.enable = lib.mkForce false;

  # The channel is deliberately omitted to keep the ABL RAM image bounded.
  # Install from a flake URL/path after networking is up, or place a normal
  # configuration.nix under /mnt/etc/nixos before invoking nixos-install.
  nix.registry = lib.mkForce { };
  system.extraDependencies = lib.mkForce [ ];

  # The kernel has CONFIG_SQUASHFS_XZ=y. XZ compresses the executable store
  # closure materially better than zstd here, and the slower decompressor is
  # paid only once while the RAM-only installer boots.
  netboot.squashfsCompression = "xz -Xdict-size 1M";

  users.users.root.initialHashedPassword = "";
  services.getty.autologinUser = "root";
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  environment.systemPackages = with pkgs; [
      bashInteractive
      e2fsprogs
      f2fs-tools
      gptfdisk
      iproute2
      iw
      installNixos
      openssh
      parted
    ] ++ [ networkmanager ];

  environment.etc."motd".text = ''
    liuqin NixOS live installer

    Network: use nmtui or nmcli. Target root must be mounted at /mnt.
    Install: liuqin-install-nixos --flake FLAKE
    The live image never partitions or formats storage automatically.
  '';

  # netboot already carries the kernel and the initial ramdisk separately.
  # Keeping those links in the stage-2 toplevel would pull the complete kernel
  # output (all DTBs and every loadable module) into the squashfs as well.
  # This filtered toplevel retains the systemd/NixOS activation surface needed
  # after the overlay root is mounted, while the boot image supplies the kernel
  # and initrd directly.
  system.build.liuqinLiveToplevel = pkgs.runCommand "liuqin-installer-live-toplevel" { } ''
    mkdir -p "$out"
    cp -a ${config.system.build.toplevel}/. "$out/"
    chmod -R u+w "$out"
    rm -f "$out/kernel" "$out/kernel-modules" "$out/dtbs" \
      "$out/initrd" "$out/firmware" "$out/boot.json" \
      "$out/extra-dependencies"

    # The live system must retain its stage-2 activation entry point: it sets
    # up the mutable /etc overlay, users, firmware path, and /run/current-system.
    # Perlless replaces the usual Perl activation snippets with userborn and
    # the /etc overlay, so only generation-switching artifacts are removed.
    rm -f "$out/dry-activate" "$out/system" "$out/switch-inhibitors"
    rm -rf "$out/specialisation"
    rm -f "$out/bin/switch-to-configuration" \
      "$out/bin/switch-to-configuration-wrapped" \
      "$out/bin/.switch-to-configuration-wrapped"

    # Remaining scripts embed the original toplevel path. Repoint those
    # textual references at this filtered tree, otherwise the store sees the
    # full system as a live dependency even after its boot-only links vanish.
    while IFS= read -r -d "" file; do
      if grep -IqF "${config.system.build.toplevel}" "$file"; then
        sed -i "s|${config.system.build.toplevel}|$out|g" "$file"
      fi
    done < <(find "$out" -type f -print0)
  '';
  netboot.storeContents = lib.mkForce [ config.system.build.liuqinLiveToplevel ];

  system.stateVersion = lib.mkDefault "26.11";
}
