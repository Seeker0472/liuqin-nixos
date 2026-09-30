# SPDX-License-Identifier: MIT
#
# NixOS live installer for the Xiaomi Pad 6 Pro. This configuration is
# intentionally separate from the installed desktop configuration: it boots
# from a tmpfs/overlay root, so it must not run the persistent-root guard or
# any service that reads device-private state from persist.
#
# The install itself is upstream and is not represented here: the operator
# partitions, formats and mounts the target, then runs nixos-install, which
# evaluates or fetches the closure into that mountpoint and activates it there
# (README.md, "Installation model"). What it carries is what this device needs
# and nixpkgs does not have: the USB control channel, the display and firmware
# hand-off, and the trimming that keeps the live root out of the squashfs.
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

  # The USB2 control channel this installer exposes: the configfs NCM/ECM
  # gadget and the busybox login wrapper are shared with the installed
  # system's debug channel (modules/liuqin/usb-shell.nix; see
  # pkgs/usb-gadget.nix). The installer assigns the address itself and raises
  # the readiness marker its udhcpd/telnetd units wait on.
  usbGadgetSetup = pkgs.mkLiuqinUsbGadget {
    product = "liuqin NixOS installer";
    configuration = "USB network installer";
    logToConsole = true;
    assignAddress = true;
  };

  usbShellLogin = pkgs.liuqinUsbLogin;

  usbDhcpConfig = pkgs.writeText "liuqin-usb-udhcpd.conf" ''
    start 192.168.7.10
    end 192.168.7.19
    interface usb0
    lease_file /run/liuqin-usb-udhcpd.leases
    pidfile /run/liuqin-usb-udhcpd.pid
    max_leases 10
    option subnet 255.255.255.0
  '';

  # The RAM installer carries its kernel and initial ramdisk inside the ABL
  # boot image, so the filtered live toplevel has no store copy of either. Its
  # bootspec must still parse and must not reference the kernel output (which
  # would drag every module and DTB into the squashfs), so both payload fields
  # point at this note.
  bootPayload = pkgs.writeText "liuqin-installer-boot-payload" ''
    This NixOS live system is a RAM image. Its kernel and initial ramdisk are
    supplied by the ABL boot image built from this flake
    (lib.mkLiuqinInstallerImages), not by the Nix store, so the bootspec's
    kernel/initrd fields point here instead of at a second copy.
  '';

  # The stage 1 this configuration selects (systemd's, i.e. the
  # !system.nixos-init.enable path forced below) locates the live closure by
  # resolving the kernel command line's init= inside /sysroot, and only
  # proceeds when that path exists. Ours is the first init=, from the boot
  # image's bootargs (init=<liuqinLiveToplevel>/init), but ABL appends its own
  # init=/init after it and the last value wins, so the raw lookup would land
  # on /sysroot/init. Take the first init= that resolves under /sysroot and
  # fall back to the store glob only when the command line carries nothing
  # usable: the glob depends on this derivation's name, and a rename must not
  # be able to turn into a silent no-boot.
  plantSysrootInit = pkgs.writeShellScript "liuqin-plant-sysroot-init" ''
    set -eu

    init_path=
    tried=
    for arg in $(${pkgs.coreutils}/bin/cat /proc/cmdline); do
      case "$arg" in
        init=*)
          candidate=''${arg#init=}
          [ -n "$candidate" ] || continue
          if [ -x "/sysroot$candidate" ]; then
            init_path="$candidate"
            break
          fi
          tried="$tried $candidate"
          ;;
      esac
    done

    if [ -z "$init_path" ]; then
      # Fallback for a command line that lost our init= entirely.
      dir=$(${pkgs.coreutils}/bin/ls -d /sysroot/nix/store/*-liuqin-installer-live-toplevel 2>/dev/null \
        | ${pkgs.coreutils}/bin/head -1)
      if [ -n "$dir" ]; then
        init_path="''${dir#/sysroot}/init"
      fi
    fi

    if [ -z "$init_path" ]; then
      echo "liuqin-plant-sysroot-init: no live closure; init= values tried:$tried; store glob matched nothing" >&2
      exit 1
    fi

    # /sysroot/init is resolved inside the live root, so the link target is an
    # in-root path, which is what the lookup reads back.
    ${pkgs.coreutils}/bin/ln -sfn "$init_path" /sysroot/init
    echo "liuqin-plant-sysroot-init: /sysroot/init -> $(${pkgs.coreutils}/bin/readlink /sysroot/init)"
  '';

in
{
  imports = [
    "${modulesPath}/installer/netboot/netboot.nix"
    "${modulesPath}/profiles/perlless.nix"
  ];

  # The installer deliberately uses its own kernel variant. It keeps the
  # validated display hand-off/earlycon behaviour, but promotes the USB gadget
  # and input paths to built-in so a RAM-only image never depends on modules.
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
    # The screen is the only early failure channel on this board. Keep the
    # early console registered for the whole session: console=tty0 alone lets
    # the DRM fbdev take over from the ABL framebuffer and disable the early
    # console at 0.0057 s, which loses the log that says what went wrong.
    "keep_bootcon"
    # console=tty0 is what gets the log and the getty; with the fbdev DRM
    # client that is fbcon on the DRM framebuffer, which patch 0012 also keeps
    # updated per draw.
    "console=tty0"
    # One path only: fw_path_para is a single char[256] (module_param_string,
    # firmware_loader/main.c) and does NOT split on ':', so a second
    # ':'-joined path invalidates the whole parameter and every firmware load
    # fails with -2 (that is how the installer's WLAN never came up:
    # ath11k/WCN6855/hw2.1/amss.bin).  The initrd mounts the liuqin firmware
    # subset at /var/lib/firmware (see below) and the loader takes the
    # compressed .zst blobs from there, exactly like the installed system does
    # with the same single-path parameter.
    "firmware_class.path=/var/lib/firmware"
  ];
  # NixOS defaults to loglevel=4, which would hide nearly all of that log and
  # (with the previous log DRM client) left the panel cleared and black. Keep
  # the kernel's own default instead, as the downstream image does.
  boot.consoleLogLevel = 7;

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

  # make-initrd-ng copies explicit store paths; it does not infer files from
  # the text of an ExecStart command. Keep every executable/configuration
  # path used by the initrd USB services in the image explicitly.
  boot.initrd.systemd.storePaths = with pkgs; [
    busybox
    coreutils
    iproute2
    util-linux
    usbGadgetSetup
    usbShellLogin
    usbDhcpConfig
    plantSysrootInit
  ];

  # The downstream first-boot image brings up the USB gadget before the live
  # root is handed over. Do the same here so a display failure does not also
  # remove the only practical diagnostic/control channel. The initrd services
  # are stopped during switch_root; the stage-2 copies below recreate the same
  # channel for the actual installation shell.
  boot.initrd.systemd.services.liuqin-usb-gadget = {
    description = "Create the liuqin USB NCM/ECM gadget in the initrd";
    wantedBy = [ "initrd.target" ];
    path = with pkgs; [ coreutils iproute2 util-linux ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${usbGadgetSetup}/bin/liuqin-usb-gadget";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "1s";
    };
  };

  boot.initrd.systemd.services.liuqin-usb-dhcp = {
    description = "Serve DHCP on the liuqin initrd USB network";
    wantedBy = [ "initrd.target" ];
    requires = [ "liuqin-usb-gadget.service" ];
    after = [ "liuqin-usb-gadget.service" ];
    path = with pkgs; [ busybox coreutils ];
    serviceConfig = {
      Type = "simple";
      ExecStartPre = [
        "${pkgs.coreutils}/bin/test -e /run/liuqin-usb-ready"
        "${pkgs.coreutils}/bin/touch /run/liuqin-usb-udhcpd.leases"
      ];
      ExecStart = "${pkgs.busybox}/bin/busybox udhcpd -f -S ${usbDhcpConfig}";
      # switch_root stops initrd services; the stage-2 copies recreate the
      # channel. During the initrd lifetime, recover from a daemon crash.
      Restart = "on-failure";
      RestartSec = "1s";
    };
  };

  boot.initrd.systemd.services.liuqin-usb-shell = {
    description = "Provide the liuqin initrd USB rescue shell";
    wantedBy = [ "initrd.target" ];
    requires = [ "liuqin-usb-gadget.service" ];
    after = [ "liuqin-usb-gadget.service" ];
    path = with pkgs; [ busybox coreutils ];
    serviceConfig = {
      Type = "simple";
      ExecStartPre = "${pkgs.coreutils}/bin/test -e /run/liuqin-usb-ready";
      ExecStart = "${pkgs.busybox}/bin/busybox telnetd -F -S -b 192.168.7.2:2323 -l ${usbShellLogin}/bin/liuqin-usb-login";
      Restart = "on-failure";
      RestartSec = "1s";
    };
  };

  # The two stage-1 lookups below decide which closure this image boots and
  # where its etc image lives. Both resolve init= inside /sysroot, and ABL's
  # trailing init=/init makes that /sysroot/init, which a netboot tmpfs root
  # does not carry. Plant the marker first; without it both units fail and the
  # live system never starts, which also removes the USB channel it provides.
  boot.initrd.systemd.services.initrd-find-nixos-closure.serviceConfig =
    { ExecStartPre = [ "${plantSysrootInit}" ]; };

  boot.initrd.systemd.services.initrd-find-etc.serviceConfig.ExecStartPre = [ "${plantSysrootInit}" ];

  # The panel is the only channel that survives a USB failure, and it starts
  # out showing nothing the console drew before the DRM fbdev took over: that
  # went to a different buffer. One blank/unblank makes fbcon redraw the whole
  # console buffer (its scrollback included) into the framebuffer the panel
  # scans, so the complete boot log ends up visible. Per-draw flushing is
  # handled in the kernel by patch 0012 and needs nothing from userspace. The
  # command is shared with the installed system (pkgs/screen-refresh.nix).
  systemd.services.liuqin-screen-refresh = {
    description = "Redraw the console into the panel framebuffer";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.liuqinScreenRefresh}/bin/liuqin-screen-refresh";
    };
  };

  # initrd systemd stops its own services at switch_root. Recreate the same
  # gadget/control channel in the live NixOS stage so the operator can keep
  # using the USB cable while preparing /mnt and running nixos-install.
  systemd.services.liuqin-usb-gadget = {
    description = "Create the liuqin USB NCM/ECM gadget";
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ coreutils iproute2 util-linux ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${usbGadgetSetup}/bin/liuqin-usb-gadget";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "1s";
    };
  };

  systemd.services.liuqin-usb-dhcp = {
    description = "Serve DHCP on the liuqin USB network";
    wantedBy = [ "multi-user.target" ];
    requires = [ "liuqin-usb-gadget.service" ];
    after = [ "liuqin-usb-gadget.service" ];
    path = with pkgs; [ busybox coreutils ];
    serviceConfig = {
      Type = "simple";
      ExecStartPre = [
        "${pkgs.coreutils}/bin/test -e /run/liuqin-usb-ready"
        "${pkgs.coreutils}/bin/touch /run/liuqin-usb-udhcpd.leases"
      ];
      ExecStart = "${pkgs.busybox}/bin/busybox udhcpd -f -S ${usbDhcpConfig}";
      Restart = "on-failure";
      RestartSec = "1s";
    };
  };

  systemd.services.liuqin-usb-shell = {
    description = "Provide the liuqin USB rescue shell";
    wantedBy = [ "multi-user.target" ];
    requires = [ "liuqin-usb-gadget.service" ];
    after = [ "liuqin-usb-gadget.service" ];
    path = with pkgs; [ busybox coreutils ];
    serviceConfig = {
      Type = "simple";
      ExecStartPre = "${pkgs.coreutils}/bin/test -e /run/liuqin-usb-ready";
      ExecStart = "${pkgs.busybox}/bin/busybox telnetd -F -S -b 192.168.7.2:2323 -l ${usbShellLogin}/bin/liuqin-usb-login";
      Restart = "on-failure";
      RestartSec = "1s";
    };
  };

  networking.hostName = "liuqin-installer";
  networking.networkmanager.enable = true;
  networking.networkmanager.package = networkmanager;
  # NetworkManager owns both association and per-connection DHCP.  Do not
  # start the separate dhcpcd service as well: it is redundant here and makes
  # the live image larger and can race NetworkManager for the same interface.
  networking.useDHCP = lib.mkForce false;
  networking.firewall.enable = false;
  # The USB address is assigned by the gadget setup helper. Keep NetworkManager
  # from replacing it with a DHCP client profile when usb0 appears.
  environment.etc."NetworkManager/conf.d/20-liuqin-usb.conf".text = ''
    [keyfile]
    unmanaged-devices=interface-name:usb0
  '';
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

  # `nixos-install` stays enabled: it is the install command README.md
  # documents, and with the wrapper gone nothing else in the image provides it.
  # The rest of the installer helpers are not needed in a RAM-only live closure
  # and only add tooling to it.
  system.tools = {
    nixos-build-vms.enable = false;
    nixos-enter.enable = false;
    nixos-generate-config.enable = false;
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

  # `nix copy` - the documented way to move the closure into /mnt, and how the
  # live shell reaches a host-side binary cache - is part of the new CLI. A
  # bare invocation otherwise fails with "experimental Nix feature 'nix-command'
  # is disabled". nixos-install's own --flake path passes its flags, but
  # --system plus an explicit copy does not.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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
      openssh
      parted
    ] ++ [ networkmanager ];

  environment.etc."motd".text = ''
    liuqin NixOS live installer

    USB control: telnet 192.168.7.2 2323 (direct trusted cable only)
    Network: use nmtui or nmcli. Target root must be ext4, labelled
    LIUQIN_ROOT, and mounted at /mnt. Its GPT partlabel must match the
    selected target configuration (linux or userdata).
    Install: partition, format and mount the target, then run
    nixos-install --root /mnt --no-channel-copy (see README.md for how the
    closure reaches the tablet without building it here).
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
      "$out/initrd" "$out/firmware" \
      "$out/extra-dependencies"

    # boot.json is the bootspec that NixOS' stage-1 reads to find the etc
    # image, the environment/modprobe binaries and the firmware path. Keep it,
    # but drop the two payload paths that exist only inside the RAM boot image:
    # the store copy must not pull a second kernel and initial ramdisk into the
    # squashfs. A NixOS init is recognised from prepare-root, which stays.
    ${pkgs.buildPackages.jq}/bin/jq --arg payload "${bootPayload}" \
      '."org.nixos.bootspec.v1".kernel = $payload
       | ."org.nixos.bootspec.v1".initrd = $payload' \
      "$out/boot.json" > "$out/boot.json.new"
    mv "$out/boot.json.new" "$out/boot.json"

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
