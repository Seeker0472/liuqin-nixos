# patches/kernel — Linux 7.2.5 device patches

`kernel/default.nix` applies every `*.patch` in this directory, byte-sorted by
filename, to a pristine 7.2.5 tree.  `*.disabled` is ignored.  Each patch
carries its provenance in the message block above the diff; keep that block
with the patch when editing one.

## The series

| # | Patch | What |
| --- | --- | --- |
| 0001 | dts-bindings | liuqin DTS + bindings (from the squashed downstream patch) |
| 0002 | hid-nanosic | WN8030 keyboard-folio bridge driver, binding, selftest |
| 0003 | touchscreen-nt36xxx | Novatek NT36523 SPI touchscreen rewrite |
| 0004 | display-dsi-panel | MSM DSI/DPU + NT36532 panel changes |
| 0005 | audio-audioreach | AudioReach/TDM/CS35L41 sound support |
| 0006 | power-pon-battmgr | qcom-pon / battmgr / pmic-glink / ucsi-glink changes |
| 0007 | media-iris-sm8450 | Qualcomm iris video decoder SM8450 support |
| 0008 | misc-of-ubwc-earlycon | earlycon on simple-framebuffer, UBWC and misc DT |
| 0009 | phy-i2c-eusb2-repeater | eUSB2 repeater (PTN3222) support |
| 0010 | pinctrl-sm8475 | SM8475 TLMM pin controller driver |
| 0011 | pinctrl-gpio-function-flag | flag the SM8475 GPIO function as GPIO |
| 0012 | msm-dirtyfb-cpu-written | flush dirtyfb for CPU-mapped framebuffers |
| 0013 | pcie-phy-cape-tables | QMP PCIe PHY gen3x2 init tables for SM8475 |
| 0014 | qcom-q6v5-quiet-duplicate-handover | quiet the duplicated remoteproc handover log |
| 0015 | msm-first-modeset-cycle | delayed first modeset cycle (panel bring-up) |
| 0016 | cpu-capacity-energy-model | Kryo cluster capacity/EM (scheduler) |
| 0017 | cpu-thermal-cooling-maps | CPU throttling thermal maps |
| 0018 | camera-camss-sm8475 | CAMSS table for SM8475 + vendor CSIPHY 2.1.3 lane table |
| 0019 | camera-sensors | IMX596 + SC202CS driver, binding, Kconfig (findings folded in) |
| 0020 | camera-s5kjn1-vendor-modes | S5KJN1 vendor 19.2 MHz mode tables |
| 0021 | camera-gt9764-autofocus | GT9764 (dw9768-compatible) stream-powered VCM |
| 0022 | camera-board-dts | board camera graph (CAMSS, three modules, flash, EEPROM) |
| 0023 | camera-camcc-gdsc | camera GDSC wait values + retain-FF (vendor values) |
| 0024 | camera-bringup-always-on | bring-up: keep titan_top/IFE GDSCs and camera AXI on |
| 0025 | camera-s5kjn1-vflip | default the wide module's vertical flip (downstream-only) |

## Numbers that are not in the tree

The camera series was consolidated before production: the bring-up series
0018–0066 (24 patches) is now 8 patches, 0018–0025.  Old number -> new home:

- 0018 camss + 0022 csiphy lane table -> 0018
- 0019 sensors + 0025/0026/0036/0051–0055/0061/0062 fixes -> 0019
- 0020 s5kjn1 vendor modes -> 0020 (unchanged)
- 0024 dw9768 + 0064 stream-powered -> 0021
- every DTS hunk (0018/0019/0021/0023/0024/0037/0051/0053/0054/0063) -> 0022
- 0028 wait values + the fix part of 0018's titan_top -> 0023
- 0030 IFE always-on + 0033 GCC AXI + titan_top's PWRSTS_ON -> 0024
- 0066 s5kjn1 vflip -> 0025

Numbers never in the tree (do not resurrect): 0043–0050, 0056–0059, 0065,
0067–0070 (never shipped); 0027/0029/0031 (bring-up debugfs: reading the
CAMNOC/VFE windows hung the SoC, reg_write had no bound check); 0038–0042
(superseded experiments; 0041 was a no-op); 0060 (global PMIC5 PLDO retune,
premise contradicted by the vendor source); the four `.patch.disabled` files
(0032/0034/0035/0071).  Their stories are in the bring-up branch's lab notes
(git history); the production summary is `docs/PORTING-NOTES.md` (Camera).

`0018-qcom-q6v5-quiet-duplicate-handover` was renamed to **0014** so that
`0018` unambiguously refers to the camera series; the rename is
content-neutral.

## Downstream bring-up workarounds (do not upstream)

Patch 0024 pins `titan_top_gdsc` and the IFE GDSCs on and keeps the GCC
camera AXI branches enabled; 0023 carries the vendor GDSC wait values, which
are the real fix.  The always-on part is a board bring-up workaround with a
small always-on power cost; the camera does not stop working because of it,
but it is not the platform's final power model.  It is kept because dropping
it has not yet been tested on hardware: a minimal-set bisect (remove one,
stream, measure) is an open item in `docs/TODO/CAMERA-MAINLINE.md`.

## Vendor provenance

0019 and 0020 embed sensor register/mode tables and 0018 the CSIPHY lane
table, all decoded during bring-up from the shipped MIUI module blobs
(`com.qti.sensormodule.*.bin` / `camera.ko`); the generator scripts lived in
the bring-up branch and are not part of production.  See `NOTICE` for the
redistribution caveat: the numbers are facts about hardware, the container
files stay operator-supplied and are not committed.

## Verifying an edit

```sh
# every hunk declares its real line counts (the build applies with GNU patch,
# which silently truncates a hunk whose count is short)
python3 kernel/check-patch-hunks.py patches/kernel/*.patch

# the series is replayable by git (a merge to main or any mail-based flow);
# run inside a pristine 7.2.5 checkout, in filename order
for f in $(ls patches/kernel/*.patch | LC_ALL=C sort); do git apply "$f"; done

# the full build asserts the camera config symbols against the final .config
nix build .#kernel
```
