# SPDX-License-Identifier: MIT
#
# Optional debug channel: the USB2 peripheral control network the RAM installer
# always has, ported to the installed system.
#
# The panel is this board's only local console, so a system whose display never
# comes up is otherwise invisible: the journal can be read afterwards from the
# RAM installer, but nothing inside the *running* system - DRM connector state,
# the framebuffer, the compositor's output - can be inspected. With this
# enabled the tablet presents 192.168.7.2/24 over USB (NCM with ECM fallback),
# serves DHCP to the host and runs a busybox telnet root shell on port 2323,
# exactly like the installer's channel.
#
# The configfs gadget is the same package the installer uses (pkgs/usb-gadget.nix)
# and usb0's address plus the DHCP server are declared to systemd-networkd
# instead of being scripted, so this module contributes only the gadget unit
# and the shell.
#
# Off by default and deliberately never enabled by the BSP: it is an
# unauthenticated root shell on a directly cabled USB link. That is the same
# trust model as the installer image, but it is not something a normal
# installation should carry without being asked.
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin.usbShell;

  gadget = pkgs.mkLiuqinUsbGadget {
    product = "liuqin NixOS debug shell";
    configuration = "USB debug network";
    # UCSI owns the Type-C role in this build (connector@0 with the role
    # switch), so the debug gadget must never ask for device itself: it binds
    # only when UCSI has already selected device mode, and steps aside for an
    # active host/DP role.  SuperSpeed descriptors are always enabled, with
    # the USB2 NCM/ECM functions kept as the fallback.
    requestDeviceRole = false;
    superSpeed = true;
  };
  unbindGadget = pkgs.writeShellScript "liuqin-usb-gadget-unbind" ''
    if [ -w /sys/kernel/config/usb_gadget/liuqin/UDC ]; then
      echo "" > /sys/kernel/config/usb_gadget/liuqin/UDC
    fi
  '';
in
{
  options.hardware.liuqin.usbShell.enable = lib.mkEnableOption ''
    the USB2 debug network and root shell: the tablet presents 192.168.7.2/24
    over USB (NCM, ECM fallback), serves DHCP to the host and runs a telnet
    root shell on port 2323, like the RAM installer. Deliberately off by
    default - it is an unauthenticated root shell on a cabled USB link'';

  config = lib.mkIf cfg.enable {
    # The debug channel is only useful if the system can be inspected: a
    # minimal NixOS carries ps and dmesg (procps and util-linux are core
    # packages) but no lspci and no lsusb, and each missing tool costs a
    # reboot round.
    environment.systemPackages = with pkgs; [ pciutils usbutils ];

    # Bind the UDC only; the address and the DHCP server come from networkd.
    systemd.services.liuqin-usb-gadget = {
      description = "liuqin USB2 debug gadget (NCM, ECM fallback)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = unbindGadget;
      };
      script = "${gadget}/bin/liuqin-usb-gadget";
    };

    systemd.network.enable = true;
    # NetworkManager owns the real connection here; this module only declares
    # usb0, which has no carrier until the cable is plugged in. The generic
    # systemd-networkd-wait-online would stall (then fail at its timeout) on
    # that link and delay network-online.target on every boot.
    systemd.network.wait-online.enable = lib.mkDefault false;
    systemd.network.networks."10-liuqin-usb0" = {
      matchConfig.Name = "usb0";
      address = [ "192.168.7.2/24" ];
      networkConfig = {
        # The gadget interface has no carrier until the host is plugged in,
        # and the DHCP server must be listening by the time it is.
        ConfigureWithoutCarrier = true;
        DHCPServer = true;
      };
      dhcpServerConfig = {
        # The 192.168.7.10-.19 range the installer's udhcpd serves.
        PoolOffset = 10;
        PoolSize = 10;
        # The installer's udhcpd sends no router or DNS either: the host must
        # not start routing through the tablet just because the cable is in.
        EmitRouter = false;
        EmitDNS = false;
      };
    };

    systemd.services.liuqin-usb-shell = {
      description = "liuqin USB debug root shell (telnet 2323)";
      wantedBy = [ "multi-user.target" ];
      requires = [ "liuqin-usb-gadget.service" ];
      after = [ "liuqin-usb-gadget.service" ];
      # telnetd -b needs 192.168.7.2 to exist and networkd assigns it
      # asynchronously; retry until then instead of tripping systemd's start
      # limit (0 disables rate limiting).
      startLimitIntervalSec = 0;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.busybox}/bin/busybox telnetd -F -S -b 192.168.7.2:2323 -l ${pkgs.liuqinUsbLogin}/bin/liuqin-usb-login";
        Restart = "on-failure";
        RestartSec = "1s";
        # Long builds are run through this shell; without this an OOM inside
        # one stops the unit and its restart SIGINTs the whole build tree
        # (a build running through this shell dies with the unit otherwise).
        OOMPolicy = "continue";
      };
    };

    # NetworkManager would claim usb0 and fight networkd's fixed address.
    networking.networkmanager.unmanaged = [ "interface-name:usb0" ];
    networking.firewall.interfaces.usb0 = {
      allowedTCPPorts = [ 2323 ];
      # The host's DHCP request has to reach networkd's server.
      allowedUDPPorts = [ 67 ];
    };
  };
}
