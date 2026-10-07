# libcamera AF patches

Eight patches against libcamera 0.7.2, applied by `default.nix` as the
standalone package `liuqinLibcameraAf` (plus per-sensor soft-IPA tuning files):

- `0001-swisp-focus-stat`: the software ISP measures a focus figure of merit
  (a normalized Tenengrad: the sum of squared luma gradients divided by the
  sum of squared luma, over the central 3/5 of the processed frame) next to
  the sums and histogram, on both debayer paths (CPU and EGL), and publishes
  it in `SwIspStats`, so the autofocus algorithm consumes it like every other
  ISP statistic instead of mapping and scanning frames itself.  The
  normalization makes frames taken at different exposures comparable, which
  matters because the AF compares scores across scans.
  The CPU debayer path also sets `outputSize_` now (the EGL path already
  did); without it `SwStatsCpu::setFocus` is a no-op and the AF sees no
  measurements at all on that path.
- `0002-ipa-simple-lens-control`: the lens channel.  The soft IPA gains a
  `setLensPosition` event, and the pipeline exposes the lens driver's
  `V4L2_CID_FOCUS_ABSOLUTE` range as the core `LensPosition`/`AfMode`/
  `AfTrigger`/`AfState` controls; the IPA forwards requested moves
  (`activeState.af.lensMove`) and the pipeline handler applies them to the
  `CameraLens` it owns.  This patch also adds the shared `activeState` fields
  the AGC, AWB and AF algorithms coordinate on (`af.hold`, `agc.converged`,
  `awb.converged`, the AGC digital gain).
- `0003-ipa-simple-agc`: AGC convergence reporting, `AeEnable`, freezing
  during an AF scan (`af.hold`), and the ISP digital gain stage (on the way
  up: exposure, analogue gain, digital gain; down: the reverse), reported as
  `DigitalGain` metadata.
- `0004-ipa-simple-awb`: grey-world gains bounded by a tuning parameter
  (`max-gain`), convergence reporting, and freezing during an AF scan.
- `0005-ipa-simple-af`: contrast-detection autofocus as a simple-IPA
  algorithm (`src/ipa/simple/algorithms/af.{h,cpp}`), ported from the CDAF
  half of the RPi IPA's `Af` algorithm (BSD-2-Clause, Raspberry Pi Ltd):
  a programmed coarse scan that reverses direction when the first sample is
  too close to the peak to bracket it, early termination once the contrast
  drops below a fraction of the best sample, a fine scan around the coarse
  peak, a parabola fit for a sub-step lock, and a Settle check that only
  reports Focused when the peak was actually bracketed (Failed otherwise).
  Continuous mode rescans on a lasting scene change (contrast and the
  per-channel averages against the post-scan reference) instead of a
  score-drop heuristic.  Distances are in dioptres, converted to lens DAC by
  a `map` (its default is provisional until the module's V-curve is
  measured); the tick is one statistics frame (every 4th frame), and a scan
  armed from an unknown position waits `skip_frames` stream frames before
  its first sample (the RPi `skipFrames` accounting, in frame units).
  Tuning follows the RPi schema (`ranges`, `speeds`, `map`, `skip_frames`),
  the standard `FocusFoM` metadata is reported, and a tuning file without an
  `Af` section keeps the controls inert.  The one adaptation for the
  software ISP's normalized figure of merit is the parabola-fit conditioning
  guard, which is relative to the sample deltas instead of the RPi absolute
  constant; PDAF, the slew limiter and the IR check are not ported (there is
  no phase data on this platform, lens moves happen once per statistics
  tick, and the startup skip is `skip_frames` above).
- `0006-ipa-simple-adjust`: the saturation the ISP applies when the
  application does not set the control is a tuning parameter
  (`Adjust.saturation`) instead of a compiled-in constant.
- `0007-sensor-helpers`: per-sensor IPA helpers (S5KJN1, IMX596 and SC202CS
  gain laws and black levels).
- `0008-camera-sensor-flip-defaults`: respect a sensor driver's non-zero flip
  defaults instead of clearing them (the S5KJN1 here is mounted mirrored).

The series is upstream-bound, but the camera module injects this build only
into pipewire and wireplumber (LD_LIBRARY_PATH) instead of replacing the
closure's libcamera - that would rebuild GNOME's dependency cone.  The camera
port as a whole is documented in docs/PORTING-NOTES.md; the AF tick model and
its limits in docs/TODO/CAMERA-MAINLINE.md.
