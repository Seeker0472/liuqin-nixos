# SPDX-License-Identifier: MIT
#
# qsee-supplicant v0.1.1, the QSEE listener transport the OEM runtime links,
# with this device's UFS RPMB provider and the liuqin main() applied from
# qsee-supplicant-rpmb.patch.
#
# Vendored (not fetched): wrobelda/qsee-supplicant is a two-day-old,
# single-author repository with no larger upstream, so a pinned rev there
# could become unreachable at any time.  The vendored tree is byte-identical
# to the v0.1.1 tag (see NOTICE) and carries only what this port builds -
# src/, include/, the license files and the README; the upstream tests and CI
# are not part of it.
{ applyPatches }:

applyPatches {
  src = ./qsee-supplicant-src;
  patches = [ ./qsee-supplicant-rpmb.patch ];
}
