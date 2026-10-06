# SPDX-License-Identifier: MIT
#
# qsee-supplicant v0.1.1 (upstream), the QSEE listener transport the OEM
# runtime links, with this device's UFS RPMB provider and the liuqin main()
# applied from qsee-supplicant-rpmb.patch.
{ fetchFromGitHub, applyPatches }:

applyPatches {
  src = fetchFromGitHub {
    owner = "wrobelda";
    repo = "qsee-supplicant";
    tag = "v0.1.1";
    hash = "sha256-j+MD43WFnsGLnxBdu3up0kVPET0QRyA6f0JiGFSjuGQ=";
  };
  patches = [ ./qsee-supplicant-rpmb.patch ];
}
