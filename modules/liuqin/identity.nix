# SPDX-License-Identifier: MIT
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin;

  stateDir = "/var/lib/liuqin-private";
in
{
  config = lib.mkIf cfg.enable {
    # --- WLAN private MAC (ath11k QCA6490) --------------------------------
    # The factory MAC lives on the persist partition and is provisioned
    # into root-only state by liuqin-persist-provision.service below; this
    # unit refuses to let NetworkManager see the factory-zero address.
    systemd.services.liuqin-wlan-mac = {
      description = "liuqin private WLAN MAC admission";
      before = [ "NetworkManager.service" "network-pre.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 45;
        ExecStart = "${pkgs.liuqinWlanMac}/bin/liuqin-wlan-mac --state-file ${stateDir}/wlan-mac";
      };
    };
    systemd.services.NetworkManager = {
      requires = [ "liuqin-wlan-mac.service" ];
      after = [ "liuqin-wlan-mac.service" ];
    };

    # WLAN power save is the largest idle-power knob on the radio chain, and
    # whether it is on is invisible in this closure: mac80211's debugfs is not
    # built and nothing else can read the state, so iw is installed to check
    # it (`iw dev wlp1s0 get power_save`) and to look at link state.
    # NetworkManager would default this on anyway; stating it here keeps the
    # policy with the device instead of with an upstream default.
    networking.networkmanager.wifi.powersave = lib.mkDefault true;

    # --- Bluetooth public address -----------------------------------------
    systemd.services.liuqin-bt-preconfigure = {
      description = "liuqin QCA6490 public Bluetooth address";
      # When bluetooth.service stops, this helper stops with it.
      partOf = [ "bluetooth.service" ];
      # The controller is unconfigured on every boot (its address is volatile)
      # and this unit's "Set Public Address" is what drives the kernel's
      # unconfigured -> configured transition; that transition re-runs the
      # whole QCA setup (hci_qca sets HCI_QUIRK_NON_PERSISTENT_SETUP whenever
      # it owns the chip's power lines, as the wcn6855-pmu pwrseq path does),
      # re-downloading rampatch/NVM through firmware_class.path.  That path is
      # only usable once liuqin-firmware-path has mounted the union: the
      # stage-2 root's /var/lib/firmware carries calibration only and there is
      # no /lib/firmware, so a setup that runs first finds no qca file at all,
      # this unit fails and bluetooth.service (which Requires= it) never
      # starts.  Measured on the unit: the union finished at 12.795 s and the
      # re-download began at 12.820 s, a margin nothing guarantees.
      wants = [ "liuqin-firmware-path.service" ];
      after = [ "liuqin-firmware-path.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 150;
        ExecStart = "${pkgs.liuqinBtPublicAddr}/bin/liuqin-bt-public-addr --state-file ${stateDir}/bluetooth-address";
      };
    };
    systemd.services.bluetooth = {
      requires = [ "liuqin-bt-preconfigure.service" ];
      after = [ "liuqin-bt-preconfigure.service" ];
    };
  };
}
