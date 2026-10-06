# SPDX-License-Identifier: MIT
#
# QCBOR 1.6.1, the CBOR implementation the OEM Gatekeeper client builds
# against.  Upstream release tag; the four sources and the headers that client
# compiles are byte-identical to the copy that used to ship inside the OEM
# component's third_party tree.
{ fetchFromGitHub }:

fetchFromGitHub {
  owner = "laurencelundblade";
  repo = "QCBOR";
  tag = "v1.6.1";
  hash = "sha256-tpCW0YjTipdpYwgFVVV0pSb4OH3QoJSbhbb48/WhTFw=";
}
