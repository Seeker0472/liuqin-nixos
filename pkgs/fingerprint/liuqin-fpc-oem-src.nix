# SPDX-License-Identifier: MIT
#
# The pinned source tree of the device-specific OEM FPC1264 userspace
# component (yuzelingsha/xiaomipad-6pro-mainline at the revision below).  Only
# the component's own sources are checked out: the fingerprint clients and
# python entry points, the TOD driver and the fprintd change.  The two
# libraries they build against come from their own upstreams (qcbor.nix,
# qsee-supplicant.nix), and this port's adaptations are the patch files next
# to this one.
{ fetchgit }:

fetchgit {
  url = "https://github.com/yuzelingsha/xiaomipad-6pro-mainline";
  rev = "17c534bdc41cc7ce76d402990530809978069b73";
  sparseCheckout = [
    "device/fingerprint/oem/src/fingerprint/oem"
    "device/fingerprint/oem/src/fingerprint/libfprint-tod"
    "device/fingerprint/oem/src/fingerprint/fprintd-oem"
  ];
  hash = "sha256-f8uw6f3+D13uNfnZJ7qtYaOgsBOsu96ewSysztmpHwM=";
}
