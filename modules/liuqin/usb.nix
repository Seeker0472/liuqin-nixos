# SPDX-License-Identifier: MIT
#
# USB-C services.  The kernel is a single build that carries the whole board
# topology (USB3 peripheral data path, Type-C host/OTG, DP Alt Mode), so
# nothing here selects a hardware path: this module only wires up the MiPPS
# authentication coordinator and the tools used to inspect the Type-C and
# charger stacks.
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin;
in
{
  options.hardware.liuqin = {
    mipps = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run the AP-side MiPPS authentication coordinator.  Off by default
          because it only does anything on systems that carry the root-only
          key files (keyDirectory); without them it logs a failed FG
          authentication and clears the verdict.
        '';
      };
      reverseAuth = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Also send UVDM command 8 (reverse authentication) after a verified
          digest, using the community 6 -> 8 -> 7 order.  The stock
          batterysecret never sends command 8; hardware validation pending.
        '';
      };
      dataRoleSwap = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Request the Type-C host data role before adapter authentication,
          matching the stock batterysecret flow.  Measured with the stock
          67 W charger: the ADSP runs the vendor SVID discovery
          (adapter_svid 0x2717) only in the host role, while the FG digest is
          only valid in the sink role, so the stock ordering - FG first, then
          the swap - is what makes 67 W authentication work at all.
        '';
      };
      keyDirectory = lib.mkOption {
        type = lib.types.strMatching "/[^ ]+";
        default = "/var/lib/liuqin/mipps";
        description = "Root-only directory containing fg.key, slave-fg.key and pd-00.key.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(lib.hasPrefix "/nix/store/" cfg.mipps.keyDirectory);
        message = "MiPPS runtime keys must be kept outside /nix/store";
      }
    ];

    # The Type-C/charger inspection tools stay installed: this module is the
    # only place that knows the board's USB-C stack.
    environment.systemPackages = with pkgs; [ usbutils pciutils ]
      ++ (lib.optionals cfg.mipps.enable [ pkgs.liuqinMippsd ]);

    systemd.tmpfiles.rules = lib.mkIf cfg.mipps.enable [
      "d ${cfg.mipps.keyDirectory} 0700 root root - -"
    ];

    systemd.services.liuqin-mippsd = lib.mkIf cfg.mipps.enable {
      description = "liuqin Xiaomi MiPPS authentication coordinator";
      wantedBy = [ "multi-user.target" ];
      after = [ "pmic-glink.service" "systemd-udev-settle.service" ];
      wants = [ "systemd-udev-settle.service" ];
      path = [ pkgs.liuqinMippsd ];
      environment.LIUQIN_MIPPS_KEY_DIR = cfg.mipps.keyDirectory;
      serviceConfig = {
        Type = "simple";
        # dataRoleSwap = true (the default) selects the stock batterysecret
        # flow, which authenticates in the Type-C host role.
        ExecStart = "${pkgs.liuqinMippsd}/bin/liuqin-mippsd"
          + lib.optionalString (!cfg.mipps.dataRoleSwap) " --no-data-role-swap"
          + lib.optionalString cfg.mipps.reverseAuth " --reverse-auth";
        Restart = "on-failure";
        RestartSec = "5s";
        User = "root";
        Group = "root";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "/sys" "/run" ];
        DevicePolicy = "closed";
        RestrictAddressFamilies = [ "AF_NETLINK" "AF_UNIX" ];
      };
    };
  };
}
