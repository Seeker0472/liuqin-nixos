# SPDX-License-Identifier: MIT (this expression; see NOTICE for payloads)
#
# Write the stock QCA6490 Bluetooth NV/RF configuration table to the
# controller.  Manual tool, run as root - deliberately not a service: the
# table is board bring-up data and an operator runs it when needed (e.g. after
# a Bluetooth power toggle, which resets the controller).
#
# The kernel-side driver only downloads the rampatch/NVM files; the vendor's
# Android BT stack additionally writes this table to the controller at every
# Bluetooth enable.  Measured on the unit (2026-10-06) with identical
# rampatch/NVM, board file and rail voltages, the ATK mouse only linked with
# the device touching the tablet without it, while the same mouse worked a
# metre away on stock Android.
#
# Timing matters: hci_qca sets HCI_QUIRK_NON_PERSISTENT_SETUP, so the kernel
# re-downloads the rampatch/NVM on every controller open and that reset wipes
# the table out of the controller's RAM - including the asynchronous
# reconfigure setup that liuqin-bt-preconfigure's Set Public Address triggers
# (measured: table at 11.5 s, setup still running until 12.3 s).  This tool
# therefore waits, bounded, for the setup to complete before writing; a write
# that races a setup must simply be repeated after it.
#
# The table itself is captured from the unit's own HCI traffic and lives in
# ./liuqin-bt-nv.table (see the header there).
{ writeShellApplication
, bluez
, coreutils
, gnugrep
, util-linux
}:

writeShellApplication {
  name = "liuqin-bt-nv";

  runtimeInputs = [ bluez coreutils gnugrep util-linux ];

  text = ''
    setup_count() {
      dmesg | grep -c "QCA setup on UART is completed" || true
    }

    # FIXME: the table lives in controller RAM and every controller open wipes
    # it (HCI_QUIRK_NON_PERSISTENT_SETUP - the kernel re-downloads the
    # rampatch/NVM and that reset clears it), so this tool has to be re-run by
    # hand after every Bluetooth power toggle.  The proper fix is to carry
    # these values in the NVM image the kernel downloads, or to replay the
    # table automatically once the setup completes; until then this manual run
    # is the whole workaround.

    # The controller is normally already up under bluetoothd; power it on
    # anyway so the tool also works after `bluetoothctl power off`.  A power-on
    # here (or the one bluetoothd is doing) runs a setup; wait for it below.
    before=$(setup_count)
    btmgmt power on >/dev/null 2>&1 || true

    i=0
    while [ "$i" -lt 20 ]; do
      if [ "$(setup_count)" -gt "$before" ]; then
        break
      fi
      sleep 0.5
      i=$((i + 1))
    done
    if [ "$i" -ge 20 ]; then
      echo "liuqin-bt-nv: controller was already set up" >&2
    fi

    # One command per line, exactly the arguments of hcitool cmd.
    n=0
    while read -r line; do
      case $line in
        "" | "#"*) continue ;;
      esac
      # shellcheck disable=SC2086
      hcitool cmd $line >/dev/null 2>&1 || true
      n=$((n + 1))
    done <<'TABLE'
${builtins.readFile ./liuqin-bt-nv.table}
TABLE
    echo "liuqin-bt-nv: wrote $n controller commands"
  '';
}
