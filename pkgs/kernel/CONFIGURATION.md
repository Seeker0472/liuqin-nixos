# Kernel configuration ownership

The two kernel profiles share the same initial Kconfig answers and common
boot constraints. The installer adds only its own constraints. This is a
staged configuration, not three alternative descriptions of the same kernel.

| File | Owns | Applied when |
| --- | --- | --- |
| `config.nix` | Initial structured answers, including the validated modular dependency inputs | `generate-config.pl`, after arm64 defconfig |
| `liuqin-firstboot.config` | Common final boot constraints for both profiles | Appended, then resolved with `olddefconfig` |
| `installer.config` | Installer-only input, console and peripheral USB constraints | Appended and resolved after the common fragment |
| `camera-symbols.txt` | Camera/media assertions; does not supply configuration | Checked against the final `.config` |
| `config-transitions.json` | Reviewed exceptions where a later stage changes an explicit earlier answer | Checked before kernel compilation |

An initial `m` followed by a common `y` is intentional for 62 symbols. These
are preserved generator inputs, not a second desired final configuration.
The existing generator walks dependency questions in order; changing all of
them directly to `y` has previously caused repeated-question failures (for
example BT before RFKILL). Any simplification of these stages needs a separate
comparison of the resolved configuration.

The installer has 14 additional constraints. It promotes `HID_MULTITOUCH`
and `HID_NANOSIC` from the initial `m` to `y`, and changes the initial
`USB_XHCI_HCD` and `USB_XHCI_PLATFORM` answers from `y` to `n`. Its other
answers either agree with the initial stage or were not specified there.
The common fragment owns the display, fbdev and USB gadget configuration;
the installer must not repeat it. Identical answers in the initial stage and
a late fragment are allowed: one supplies the generator input, the other
also establishes a final build assertion.

## Checks and changes

`check-config-policy.py` consumes the evaluated Nix answers, so `mkForce`
and other override wrappers do not hide their values. It rejects:

- Duplicate assignments within a fragment, even when their values agree.
- Installer assignments to common-fragment symbols, including equal values.
- Cross-stage value changes without an explicit transition and reason.
- Stale or duplicate transition rules, and malformed fragment assignments.
- Explicit answers that contradict the camera assertions.

Both kernel builds run this audit in `postPatch`. A standalone flake check
runs the audit and its positive/negative fixtures without compiling a kernel:

```sh
nix build .#checks.x86_64-linux.liuqin-kernel-config-policy
cat result/ownership.tsv
```

The report lists each symbol's requested values and the file that owns its
last explicit answer in each profile. It describes BSP inputs, **not** the
Kconfig-resolved output or consumer overrides. Defconfig, dependency selects
and `olddefconfig` can still affect the result. Camera requirements inherited
from the kernel rather than an explicit answer are marked `defconfig/Kconfig`.
Currently `DMABUF_HEAPS` and `DMABUF_HEAPS_SYSTEM` come from arm64 defconfig;
the final build assertions still cover both.

The existing final `.config` assertions remain mandatory: `y` must remain
built in, `m` may become `y`, and `n` may be absent when dependencies hide it.
ZRAM is the explicit exception and must remain `m`, because its userspace
setup passes module parameters. The kernel output's `kernel-config-final`
records the actual resolved configuration.

When adding a setting, choose its stage first. Keep common boot requirements
in the common fragment and installer-only requirements in the installer
delta. If it changes an earlier answer, add a narrowly scoped transition
with its reason. Do not whitelist a conflict merely to make the check pass.
Changing a common constraint only for the installer requires redesigning the
final assertions as well; the current profiles intentionally share them.

`boot.kernelPatches` and direct `structuredExtraConfig` overrides still enter
the initial generation stage. Late boot constraints continue to take
precedence. The ownership audit checks repository policy, not a consumer's
arbitrary patches; final boot assertions protect both profiles in either case.
