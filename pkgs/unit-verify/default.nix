# SPDX-License-Identifier: MIT
{ writeShellApplication, python3, systemd }:
writeShellApplication {
  name = "liuqin-unit-verify";
  text = ''
    exec ${python3}/bin/python3 ${./verify.py} \
      --systemd-analyze ${systemd}/bin/systemd-analyze "$@"
  '';
}
