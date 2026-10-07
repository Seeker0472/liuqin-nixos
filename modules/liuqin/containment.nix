# SPDX-License-Identifier: MIT
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin;
in
{
  config = lib.mkIf cfg.enable {
    # --- Gunyah node containment ------------------------------------------
    # ABL's DTBO injects /hypervisor (compatible "qcom,gunyah-vm") into the
    # live tree; systemd-detect-virt keys off it and sends GSD down VM code
    # paths. The kernel never binds a driver to the node, so a bind mount of
    # an empty directory over the devicetree export restores an honest
    # "none" for userspace readers.
    systemd.services.liuqin-hide-gunyah-node = {
      description = "Hide the ABL-injected Gunyah /hypervisor node from userspace";
      wantedBy = [ "sysinit.target" ];
      unitConfig = {
        DefaultDependencies = false;
        Conflicts = "shutdown.target";
        Before = [ "sysinit.target" "shutdown.target" ];
        ConditionPathExists = "/sys/firmware/devicetree/base/hypervisor";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /run/liuqin-empty";
        ExecStart = "${pkgs.util-linux}/bin/mount --bind /run/liuqin-empty /sys/firmware/devicetree/base/hypervisor";
        ExecStop = "${pkgs.util-linux}/bin/umount /sys/firmware/devicetree/base/hypervisor";
      };
    };
  };
}
