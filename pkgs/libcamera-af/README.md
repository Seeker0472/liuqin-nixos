# libcamera AF patches

Seven patches against libcamera 0.7.2, applied by `default.nix` as the
standalone package `liuqinLibcameraAf` (plus per-sensor soft-IPA tuning files):

- `0001-simple-lens-position`: the simple pipeline picks up the focus lens
  (GT9764/dw9768) and exposes its range as the core LensPosition control
  (raw lens units; no dioptre mapping is calibrated yet);
- `0002-simple-contrast-af`: a contrast-detection AF state machine honouring
  AfMode/AfTrigger - its known limits are the FIXME block inside the patch;
- `0003-sensor-helpers`: per-sensor IPA helpers for the liuqin sensors;
- `0004-ae-digital-gain`, `0005-adjust-default-saturation`,
  `0006-respect-flip-defaults`, `0007-awb-gain-bound`: the AE, colour and
  geometry fixes measured on the device.

The series is upstream-bound, but the camera module injects this build only
into pipewire and wireplumber (LD_LIBRARY_PATH) instead of replacing the
closure's libcamera - that would rebuild GNOME's dependency cone.  The camera
port as a whole is documented in docs/PORTING-NOTES.md.
