#!/usr/bin/env bash
# Keep pkgs/u-boot/{patches,files} and the liuqin-dualboot dev tree in exact sync, and
# prove it: baseline + patches + files must reproduce that tree byte for byte.
#
#   ./verify-port.sh              check only; fails if the packaging is stale
#   ./verify-port.sh --write      re-cut patches/ and files/ from the dev tree
#                                 and regenerate port.manifest
#
#   PORT_TREE=/path/to/source ./verify-port.sh     use another dev tree
#   BASELINE=/path/to/tree    ./verify-port.sh     use another baseline checkout
#
# The dev tree (liuqin-dualboot/u-boot/source) is the single source of truth for
# the port; this packaging is a mechanical function of it. A file the baseline
# already has goes into patches/ (grouped by topic, see patch_groups below), a
# file the port adds goes into files/. Being a function of the tree is what makes
# the product consistent: the same U-Boot comes out of both build paths.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
flake=$(cd "$here/../.." && pwd)
port=${PORT_TREE:-$here/../../../liuqin-dualboot/u-boot/source}
write=no
[ "${1:-}" = "--write" ] && write=yes

die() { echo "verify-port: $*" >&2; exit 1; }

# Topic groups for the changed files. Disjoint by construction - the script
# asserts that - which is why the series applies cleanly in any order.
patch_groups="
0001-kconfig-symbols.patch:arch/arm/Kconfig arch/arm/mach-snapdragon/Kconfig
0002-mach-board-hooks.patch:arch/arm/mach-snapdragon/board.c
0003-host-pwd.patch:Makefile
0004-console-and-input.patch:common/console.c drivers/input/input.c
0005-ufs-sm8475.patch:drivers/phy/qcom/phy-qcom-qmp-ufs.c drivers/ufs/ufs-qcom.c drivers/ufs/ufs.c include/ufs.h
0006-usb2-phy.patch:drivers/phy/qcom/phy-qcom-snps-eusb2.c
0007-usb-dwc3.patch:drivers/usb/dwc3/core.c drivers/usb/dwc3/core.h drivers/usb/dwc3/dwc3-generic.c drivers/usb/dwc3/ep0.c drivers/usb/dwc3/gadget.c
0008-fastboot-hooks.patch:drivers/fastboot/fb_command.c drivers/fastboot/fb_common.c drivers/fastboot/fb_getvar.c include/fastboot.h
0009-fastboot-gadget-pool.patch:drivers/usb/gadget/f_fastboot.c
0010-pinctrl-gpio-regulator-smmu.patch:drivers/gpio/qcom_pmic_gpio.c drivers/iommu/qcom-hyp-smmu.c drivers/pinctrl/pinctrl-uclass.c drivers/pinctrl/qcom/pinctrl-sm8450.c drivers/power/regulator/qcom-rpmh-regulator.c
0011-partlog-command.patch:cmd/Kconfig cmd/Makefile
0012-bootmenu-redisplay.patch:cmd/bootmenu.c
0013-pxe-extlinux-key-menu.patch:boot/pxe_utils.c
"

[ -d "$port" ] || die "no dev tree at $port (set PORT_TREE)"
git -C "$port" rev-parse --git-dir > /dev/null 2>&1 ||
  die "$port is not a git checkout: its tree is what defines the port"
port=$(cd "$port" && pwd)

# Device-free half of this check: patches/ and files/ are pinned by
# port.manifest, so a hand edit that bypasses --write fails `nix flake check`
# without needing the dev tree or the baseline. --write regenerates it below.
if [ "$write" = no ]; then
  ( cd "$here" && sha256sum -c --quiet port.manifest ) ||
    die "patches/ or files/ do not match port.manifest: re-run with --write"
fi

if [ -n "${BASELINE:-}" ]; then
  baseline=$(cd "$BASELINE" && pwd)
else
  # The same tree the derivation builds from, so the check cannot drift from it.
  baseline=$(nix build --no-link --print-out-paths "$flake#uboot.src") ||
    die "cannot realise the baseline source"
fi
[ -d "$baseline" ] || die "no baseline tree at $baseline"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# --- the three file lists -----------------------------------------------------
( cd "$baseline" && find . -type f | sed 's|^\./||' | sort ) > "$work/base.disk"
( cd "$port" && find . -path ./.git -prune -o -path ./.output -prune -o -type f -print |
    sed 's|^\./||' | sort ) > "$work/port.disk"
# Everything the port's checkout ignores: mostly build output (.output/ and host
# tools that land in the source tree, e.g. scripts/basic/fixdep), plus upstream
# files its own .gitattributes marks export-ignore. Anything here that is *not*
# in the baseline is named below rather than skipped quietly.
git -C "$port" ls-files -oi --exclude-standard | while IFS= read -r f; do
  [ -f "$port/$f" ] && echo "$f" || true
done | sort > "$work/port.ignored"

comm -23 "$work/port.disk" "$work/base.disk" > "$work/added.raw"

# Files that exist only because this is a checkout rather than the archive the
# build consumes: upstream's lwip submodule carries dotfiles its own
# .gitattributes marks export-ignore (the baseline ships 719 of its files, not
# these), and its per-directory .gitignore dodges the repo's ".*" ignore rule
# through the usual "!.gitignore". Nothing here is the port's work - CONFIG_LWIP
# is off - and the baseline supplies everything the build needs, so they are not
# copied into files/.
checkout_only='^lib/lwip/lwip/'
comm -23 "$work/added.raw" "$work/port.ignored" > "$work/added.nonignore"
grep -v -e "$checkout_only" "$work/added.nonignore" > "$work/added" || true
comm -23 "$work/added.raw" "$work/added" > "$work/skipped"
comm -23 "$work/base.disk" "$work/port.disk" > "$work/deleted"
comm -12 "$work/base.disk" "$work/port.disk" | while IFS= read -r f; do
  cmp -s "$baseline/$f" "$port/$f" || echo "$f"
done > "$work/changed"

if [ -s "$work/deleted" ]; then
  echo "the port deletes files the baseline has:" >&2
  cat "$work/deleted" >&2
  die "patch+copy cannot express a deletion; handle these explicitly"
fi

echo "baseline   $baseline"
echo "dev tree   $port"
echo "changed    $(wc -l < "$work/changed") 个（改）  $(wc -l < "$work/added") 个（新增）"
echo "           $(wc -l < "$work/port.ignored") 个被 checkout 忽略（构建产物/export-ignore）"
while IFS= read -r f; do echo "             跳过（非基线）: $f"; done < "$work/skipped"

# --- every changed file in exactly one group ---------------------------------
: > "$work/grouped"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  for f in ${line#*:}; do
    printf '%s %s\n' "${line%%:*}" "$f" >> "$work/grouped"
  done
done <<< "$patch_groups"
cut -d' ' -f2- "$work/grouped" | sort > "$work/grouped.files"
sort -u "$work/grouped.files" > "$work/grouped.uniq"
[ "$(wc -l < "$work/grouped.files")" = "$(wc -l < "$work/grouped.uniq")" ] ||
  die "a file is in more than one patch group: $(uniq -d "$work/grouped.files" | tr '\n' ' ')"
diff -u "$work/changed" "$work/grouped.uniq" >&2 ||
  die "the patch groups do not cover the changed files exactly"

# --- the patch names in three places must agree ------------------------------
# The groups below own the names, default.nix lists what the derivation applies,
# and patches/ is what exists on disk. A name that appears in one and not in the
# others means a patch silently does not reach the image, so all three are
# compared: groups vs default.nix always, groups vs disk unless we are about to
# rewrite disk.
cut -d: -f1 <<< "$patch_groups" | grep -v -e '^$' | sort > "$work/groups"
grep -o '\./patches/[A-Za-z0-9._-]*\.patch' "$here/default.nix" |
  sed 's|^\./patches/||' | sort > "$work/listed"
diff -u "$work/listed" "$work/groups" >&2 ||
  die "default.nix does not list exactly the patch groups of this script"

pkgdir=$here
if [ "$write" = yes ]; then
  mkdir -p "$work/stage/patches" "$work/stage/files"
  pkgdir="$work/stage"
else
  ( cd "$pkgdir" && ls patches/*.patch | sed 's|^patches/||' | sort ) > "$work/ondisk"
  diff -u "$work/groups" "$work/ondisk" >&2 ||
    die "patches/ does not match this script's groups: re-run with --write"
fi

# --- cut the packaging into $pkgdir (--write) or leave it alone --------------
if [ "$write" = yes ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name=${line%%:*}
    : > "$pkgdir/patches/$name"
    for f in ${line#*:}; do
      printf 'diff --git a/%s b/%s\n' "$f" "$f" >> "$pkgdir/patches/$name"
      diff -u --label "a/$f" --label "b/$f" "$baseline/$f" "$port/$f" >> "$pkgdir/patches/$name" || true
    done
    printf '  %-40s %s 行\n' "$name" "$(wc -l < "$pkgdir/patches/$name")"
  done <<< "$patch_groups"
  while IFS= read -r f; do
    mkdir -p "$pkgdir/files/$(dirname "$f")"
    cp -a "$port/$f" "$pkgdir/files/$f"
  done < "$work/added"
  echo "  files/ $(wc -l < "$work/added") 个移植自有文件（已暂存，校验通过后才落盘）"
fi

# --- the check: baseline + patches + files == dev tree -----------------------
cp -a "$baseline/." "$work/check"
chmod -R u+w "$work/check"   # the baseline is a read-only store path
for p in "$pkgdir"/patches/*.patch; do
  patch -s -p1 -d "$work/check" < "$p" || die "patch failed to apply: $p"
done
cp -a "$pkgdir/files/." "$work/check/"

sort -u "$work/added" "$work/base.disk" > "$work/pkg"   # everything the packaging produces
while IFS= read -r f; do
  [ -f "$work/check/$f" ] || die "the packaging loses $f"
  cmp -s "$work/check/$f" "$port/$f" ||
    die "the packaging does not reproduce $f ($(cmp "$work/check/$f" "$port/$f" 2>&1 | head -1))"
done < "$work/pkg"

( cd "$work/check" && find . -type f | sed 's|^\./||' | sort ) > "$work/rebuilt"
comm -23 "$work/rebuilt" "$work/port.disk" > "$work/unexpected"
if [ -s "$work/unexpected" ]; then
  cat "$work/unexpected" >&2
  die "the packaging produces files the dev tree does not have"
fi

if [ "$write" = yes ]; then
  # All of the above passed, so the staged result is known good: swap it in.
  rm -f "$here"/patches/*.patch
  rm -rf "$here/files"
  cp -a "$work/stage/patches/." "$here/patches/"
  cp -a "$work/stage/files/." "$here/files/"
  # Regenerate the device-free byte pin together with the packaging.
  ( cd "$here" && find files patches -type f -print0 | sort -z | xargs -0 sha256sum > port.manifest )
  echo "已写入 patches/、files/ 与 port.manifest"
fi

echo "OK: baseline + $(ls "$here"/patches/*.patch | wc -l) 个补丁 + files/ == dev 树，逐字节（$(wc -l < "$work/pkg") 个文件）"
