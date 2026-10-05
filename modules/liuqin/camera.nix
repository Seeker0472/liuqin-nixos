# SPDX-License-Identifier: MIT
#
# Camera capture stack for the demo target: v4l-utils + libcamera, the late
# sensor-module load, and the dma-buf access the software ISP needs.
#
# Background (docs/PORTING-NOTES.md, Camera): all three modules capture on
# mainline, but they share one CSID/RDI pair (csid0 -> vfe0_rdi0), so the media
# graph must be routed to exactly one of them before a stream - a leftover
# phy->csid link makes the CSID resolve two inputs and *no* camera streams.
# Nothing routes at boot: with libcamera installed, wireplumber probes the
# cameras when the GNOME session starts, and probing an already-routed media
# graph wedged the SoC's camera path (observed 2026-10-05: the boot stopped
# right after "Started session ... of user demo").  libcamera routes per
# stream; `cam --stream role=raw`, `media-ctl -r` and `v4l2-ctl` cover the
# manual cases (docs/PORTING-NOTES.md, Camera).
#
# Caveats:
#   - The cameras are reachable through the portal/pipewire path (libcamera's
#     simple pipeline + software ISP), but the single shared CSID allows one
#     streaming consumer at a time: a stray reader - another app - makes the
#     next open fail with EBUSY.
#   - On a GNOME session, wireplumber's v4l2 monitor holds the camera device
#     nodes open; if a capture fails with EBUSY, mask it for the session
#     (`systemctl --user mask wireplumber`) and re-run the capture
#     (docs/PORTING-NOTES.md).
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin.camera;

  # Bounded retry for the sensor-module load (see liuqin-camera-probe below).
  # A single line on purpose: systemd parses the ExecStart value and there is
  # no need to lean on multi-line quoting.  No `$`, so systemd's ExecStart
  # variable expansion has nothing to mangle.
  cameraProbeRetry = "for _ in 1 2 3; do ${pkgs.kmod}/bin/modprobe qcom_liuqin_sensors && exit 0; echo \"liuqin-camera-probe: modprobe failed; retrying\" >&2; sleep 5; done; exit 1";
in
{
  options.hardware.liuqin.camera.enable = lib.mkEnableOption ''
    the camera capture stack: v4l-utils and libcamera, the late sensor-module
    load, and the dma-buf access the software ISP needs'';

  options.hardware.liuqin.camera.autofocus = {
    enable = lib.mkEnableOption ''
      EXPERIMENTAL: autofocus support.  Applies the local libcamera series
      (core LensPosition control + contrast-detection AF in the simple
      pipeline; see pkgs/libcamera-af/) on top of the stock libcamera.
      Patching libcamera rebuilds it and everything linking it (pipewire
      and its dependents) and the series is upstream-bound, so this stays
      off until it lands upstream.  Requires hardware.liuqin.camera.enable'';
  };

  config = lib.mkMerge [
    # autofocus is a sub-switch of camera.enable: without the parent it
    # configures nothing.  Warn rather than assert so an eval of such a
    # configuration still succeeds.
    {
      warnings =
        lib.optional (!cfg.enable && cfg.autofocus.enable)
          "hardware.liuqin.camera.autofocus.enable has no effect without hardware.liuqin.camera.enable";
    }

    (lib.mkIf cfg.enable {
      # A camera-path wedge takes the SoC down before journald's default 5 min
      # flush, losing exactly the last minutes of kernel log - the only
      # post-mortem channel this board has.  Flush at least every few seconds.
      services.journald.settings.Journal = { SyncIntervalSec = "5s"; };

      # EXPERIMENTAL (hardware.liuqin.camera.autofocus.enable): hand the AF
      # library to the two processes that run libcamera in a GNOME session.
      # pipewire is where the portal's camera stream actually lives (its SPA
      # libcamera plugin), wireplumber enumerates/permission-checks; both are
      # pointed at the same-soname patched build.  See pkgs/libcamera-af/ for
      # why this is not a closure-level libcamera override yet.
      systemd.user.services.pipewire.environment.LD_LIBRARY_PATH =
        lib.mkIf cfg.autofocus.enable "${pkgs.liuqinLibcameraAf}/lib";
      systemd.user.services.wireplumber.environment.LD_LIBRARY_PATH =
        lib.mkIf cfg.autofocus.enable "${pkgs.liuqinLibcameraAf}/lib";

      environment.systemPackages = with pkgs;
        [ v4l-utils libcamera ]
        ++ lib.optional cfg.autofocus.enable pkgs.liuqinCamAf;

      # libcamera's software ISP needs a dma-buf provider; without it the simple
      # pipeline logs "Could not open any dma-buf provider ... disabling software
      # debayering" and there is no AE/AWB/debayer.  The kernel has
      # CONFIG_DMABUF_HEAPS{,_SYSTEM}=y/m but the module is not autoloaded.
      boot.kernelModules = [ "system_heap" ];

      # The camera sensor module's i2c comes up marginal when uDev autoloads it
      # during early boot (rails/clocks still settling): the front sensor then
      # fails its chip-id read, the v4l2 async notifier stays incomplete and
      # *every* camera disappears until a reboot (and touching the stack in that
      # state can wedge the SoC).  Blacklist the autoload and load it from a
      # oneshot once the system is up - the same probe then succeeds reliably.
      #
      # The late load can still lose the probe roulette on a flaky attempt, so
      # the oneshot retries it three times with a pause; if all three fail the
      # unit fails visibly instead of silently leaving no cameras.
      boot.blacklistedKernelModules = [ "qcom_liuqin_sensors" ];
      systemd.services.liuqin-camera-probe = {
        description = "load the camera sensor module once the system settled";
        wantedBy = [ "multi-user.target" ];
        after = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.bash}/bin/bash -c ${lib.escapeShellArg cameraProbeRetry}";
        };
      };

      # The dma-buf heaps come up as root:root 0600, which blocks the software
      # ISP running in a user session (libcamera / pipewire).  Hand over only
      # the heaps libcamera's soft ISP iterates, in its preference order
      # (src/libcamera/dma_buf_allocator.cpp): the CMA heap, named linux,cma -
      # or reserved when a cma= size is on the kernel command line - then the
      # system heap.  /dev/udmabuf is a different device and is not reached
      # while the system heap is available, so it is not granted here.
      services.udev.extraRules = ''
        SUBSYSTEM=="dma_heap", KERNEL=="linux,cma", GROUP="video", MODE="0660"
        SUBSYSTEM=="dma_heap", KERNEL=="reserved", GROUP="video", MODE="0660"
        SUBSYSTEM=="dma_heap", KERNEL=="system", GROUP="video", MODE="0660"
      '';

      # There is deliberately no idle "seat the VCM" service either: the VCM
      # and the sensor share the camera module's power (the sensor driver
      # switches it), so a lens position only exists while the module is
      # powered - with the module down the coil is off and the lens relaxes.
      # Focus is an in-session action: libcamera drives the lens while
      # streaming (see hardware.liuqin.camera.autofocus), or
      # `v4l2-ctl --set-ctrl focus_absolute=<dac>` does it during a capture.
    })
  ];
}
