# The demo target: the example configuration plus the camera stack that needs
# the still upstream-bound libcamera autofocus series (injected into the
# session's libcamera consumers).  See docs/PORTING-NOTES.md (Camera) for the
# hardware facts and open items.
{ lib, ... }:
{
  imports = [ ../examples/demo/configuration.nix ];

  # ssh-ng:// deployments (lq-deploy-direct) need the demo user to be
  # trusted by the remote daemon; the legacy ssh:// store did not.
  nix.settings.trusted-users = [ "root" "demo" ];

  hardware.liuqin.camera.autofocus.enable = true;
}
