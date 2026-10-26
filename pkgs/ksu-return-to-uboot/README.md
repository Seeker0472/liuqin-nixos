# Return to U-Boot from Android

This KernelSU module selects slot B **after Android has completed booting**.
On this project's dual-boot layout, Android is in `boot_a` and the U-Boot menu
image is in `boot_b`. The module does not reboot immediately: the next normal
reboot enters the U-Boot menu.

Build the installable ZIP through Nix from the repository root:

```sh
nix build .#ksu-return-to-uboot --out-link result-ksu
```

Install `result-ksu/liuqin-return-to-uboot-1.0.0.zip` in KernelSU Manager,
then boot Android normally from slot A. Check the result before restarting:

```sh
adb shell su -c '/data/adb/ksu/bin/bootctl get-current-slot'      # 0: this Android boot
adb shell su -c '/data/adb/ksu/bin/bootctl get-active-boot-slot' # 1: next boot
adb shell su -c '/system/bin/logcat -d -s liuqin-return-to-uboot'
```

The module checks that the device is `liuqin`, Android has finished booting
from slot A, the Boot Control HAL reports exactly two slots, and `boot_b`
has the Android boot-image magic and the liuqin U-Boot log prefix. It then calls
KernelSU's `bootctl set-active-boot-slot 1`, syncs storage, and asks the HAL whether slot B
is active and bootable. A failed check stops the script and logs the reason.

The image checks are only basic guards. Flash this repository's verified
U-Boot `boot.img` into `boot_b` before enabling the module. A modified Android
ROM must supply a working `/data/adb/ksu/bin/bootctl` and the HIDL 1.2 Boot
Control HAL. The slot switch must update Qualcomm GPT attributes, A/B type
GUIDs, and the UFS boot LUN together. This is the behavior of the published
Qualcomm implementation; `get-active-boot-slot` alone verifies only the GPT
selection.

Verified on a liuqin running Android 15: after installing the module and
rebooting Android from A, the boot-completed log reported success, the next
boot slot changed from 0 to 1, and the UFS boot LUN changed from 1 to 2. The
primary and backup GPT headers and entry arrays passed CRC checks and matched;
all 11 present type-GUID pairs in this project's U-Boot switching list were
swapped. The tablet was left running Android in A with B selected for its next
normal reboot.

The module reselects B on every completed Android boot. If you need Android to
remain the default across reboots, disable this module in KernelSU Manager.
An Android OTA can replace `boot_b` or select another slot, so do not run an
OTA on this dual-boot layout without handling its partition writes first.
