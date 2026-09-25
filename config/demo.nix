# SPDX-License-Identifier: MIT
#
# The BSP's demo target, built as `nixosConfigurations.demo`: it is literally
# the same module the consumer template ships, so examples/demo/configuration.nix
# is the single source and there is nothing to keep in sync.  Keep this file as
# the entry point rather than pointing the flake at examples/ directly, so the
# demo target does not depend on where the example happens to live.
import ../examples/demo/configuration.nix
