# pkgs/kernel/patches — Linux 7.2.5 device patches

`pkgs/kernel/default.nix` applies every `*.patch` in this directory to a pristine
7.2.5 tree in **byte-sorted filename order**, except the patches listed in its
`dtPatchNames` (`0014-…`, `0015-…` and `0016-…` today), which are applied
last.  Each patch carries a prose header above its diff; keep that header
when editing one.

The 20 patches are grouped by subsystem.  The first 14 were merged down from
a 33-patch bring-up series (the merge provenance is in each patch header);
the merged set produces a byte-identical tree, so that part is a pure
re-grouping.  0015 adds the WCD9385 SoundWire capture graph on top of the
board DTS the other patches build, 0016 names the four CS35L41 amplifiers so
the driver selects this board's firmware, 0017-0019 add the fingerprint
series (the QSEECOM TEE transport, the FPC1264 control interface and its board
DT node), and 0020 pins the WCN6855 RF rail voltages to the stock DTB.

## The series

| # | Patch | What |
| --- | --- | --- |
| 0001 | board-dts-bindings | the board DTS, its compatibles/bindings, dtsi fixes, dtb Makefile entry |
| 0002 | input-hid-touchscreen | Nanosic WN8030 keyboard folio + Novatek NT36xxx touchscreen |
| 0003 | display-panel-msm | NT36532 DSI panel, msm dirtyfb fix, warm-start fixes (stop the DSI controller, no bootloader-PLL replay) and one early DPMS off/on after the first modeset |
| 0004 | audio-audioreach | audioreach/sc8280xp path, cs35l41, wm_adsp, q6apm |
| 0005 | power-pmic-glink-mipps | PON/pmic-glink + the qcom_battmgr MiPPS ABI and CC orientation |
| 0006 | media-iris | IRIS VPU platform for sm8450 |
| 0007 | soc-misc-earlycon | UBWC table, earlycon-simplefb, quiet q6v5 handover |
| 0008 | usb-typec-dp | eUSB2 repeater PHY, sm8450 combo-PHY tables, UCSI PPM reset, vendor SVID altmode, DP link capacity |
| 0009 | pinctrl-sm8475 | sm8475 TLMM driver + gpio-function flag |
| 0010 | pcie-qmp-phy | QMP PCIe PHY cape tables |
| 0011 | cpu-topology-thermal | board CPU capacity/energy model + sm8450 thermal cooling maps |
| 0012 | camera-core | CAMSS sm8475, sensor drivers, board camera DTS |
| 0013 | camera-tuning | s5kjn1 vendor modes/vflip, gt9764 autofocus, camcc/gcc GDSC always-on |
| 0014 | board-usb-typec-dp-dt | board DTS for USB3 device, Type-C host/OTG and DP Alt Mode |
| 0015 | audio-wcd-capture | WCD9385 RX/TX SoundWire capture graph, guarded UCM `Mic`, 2.75 V micbias (applied after 0014) |
| 0016 | cs35l41-subsystem-id | name the four CS35L41 amplifiers so the driver picks linux-firmware's Halo build keyed by 10251826 (applied after 0015) |
| 0017 | tee-qseecom-legacy-transport | legacy QSEECOM TEE transport + SCM listener/app-load + mdt image assembler |
| 0018 | misc-fpc1020 | FPC1264 power/reset/IRQ control (/dev/fpc1020), no SPI (trustlet owns the bus) |
| 0019 | dts-fpc1264 | fingerprint control node: GPIO40/41 + LDO9; QUP SE10 stays reserved/disabled |
| 0020 | wcn6855-rfa-rail-voltages | pin the WCN6855 RF rail voltages to the stock DTB's init voltages |

0017-0019 are the fingerprint (FPC1264/QSEECOM) series.  0017 and 0018 apply in
sequence with the rest and 0019 (the board DT node) applies there as well: it
does not touch the regions the three DT patches applied last rewrite.

## Why 0014, 0015 and 0016 are applied last

The board DTS is built up in layers: 0001 creates it, 0011 and 0012 extend
it, and 0014 adds the USB/Type-C/DP nodes on top.  0015 extends the same file
with the WCD9385 capture graph, and 0016 appends the amplifier
`cirrus,subsystem-id` overrides.  `pkgs/kernel/default.nix` keeps all three in
`dtPatchNames` so they are applied after the sorted series, in that order.

## Adding or regenerating a patch

`pkgs/kernel/check-patch-hunks.py` runs inside the build (postPatch) and fails the
build if a patch's declared hunk counts do not match its body — the failure
mode that once silently dropped the tail of a creation hunk.

To re-group or edit the series without guessing, use a scratch git repo of the
touched files and let git produce the diffs:

```sh
# 1. extract only the files the series touches from the 7.2.5 tarball
mkdir /tmp/kfix && cd /tmp/kfix
grep -h '^+++ b/' pkgs/kernel/patches/*.patch | sed 's|^+++ b/||' | sort -u > paths.txt
tar -tJf linux-7.2.5.tar.xz > members.txt
awk 'NR==FNR{m[$0]=1;next}{if (m["linux-7.2.5/"$0]) print "linux-7.2.5/"$0}' \
    members.txt paths.txt > extract.txt
tar -xJf linux-7.2.5.tar.xz -T extract.txt && cd linux-7.2.5
git init -q && git add -A && git commit -qm pristine

# 2. apply the series in build order, committing per group
for p in $(ls <patchdir>/*.patch | sort); do patch -p1 --batch -N < "$p"; done
git add -A && git commit -qm target

# 3. regenerate a group's patch as a single diff between two commits
git diff <before> <after> > 00NN-liuqin-<group>.patch
```

Then verify the way this series was verified: replay the regenerated patches
onto a pristine checkout and require `git diff <target> HEAD` to be **empty**.

## Whole-file replacement: the DP half of the combo PHY

`pkgs/kernel/default.nix` (postPatch) copies `pkgs/kernel/replaced/phy-qcom-qmp-combo.c`
over `drivers/phy/qualcomm/phy-qcom-qmp-combo.c` after the series is applied
(it is generated from the live register state of the vendor stack; see the
comment there).  A replay therefore ends with that copy as well:

```sh
cp pkgs/kernel/replaced/phy-qcom-qmp-combo.c <pristine>/drivers/phy/qualcomm/
```

Without it the diff is non-empty, and the file is the one part of the kernel
tree that `check-patch-hunks.py` cannot see.
