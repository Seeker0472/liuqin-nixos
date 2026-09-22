# SPDX-License-Identifier: MIT
#
# boot.img for liuqin: kernel Image.gz + ABL-facing DTB + (optional) initrd,
# assembled with the pinned AOSP mkbootimg.
#
# DTB pipeline (all with stock dtc/fdtoverlay, no Python in the build):
#   1. compile the ABL metadata overlay (dts/liuqin-abl-boot-overlay.dts,
#      a /plugin/ DTS) with `dtc -@`
#   2. apply it onto the kernel's sm8475-xiaomi-liuqin.dtb with fdtoverlay
#      (fdtoverlay preserves the base's __symbols__; verified with dtc 1.7.2)
#   3. synthesize an `entry.<N>`-style DTBO whose only fragment targets
#      /__symbols__ and re-exports every label that any stock DTBO entry or
#      stock base DTB exports, all pointing at an inert sink node. This
#      replaces the downstream abl-symbols.py with pure dtc/fdtoverlay:
#      applying a DTBO against a __symbols__ fragment merges entries into
#      the base's __symbols__ instead of rewriting them.
#   4. apply that DTBO with fdtoverlay.
#
# The stock DTBO entries and stock base DTBs are fixed-output inputs
# (devices-only data extracted from the stock ROM; they never change).
{ lib
, stdenvNoCC
, fetchurl
, zstd
, dtc
, gzip
, gnugrep
, gawk
, coreutils
, findutils
, mkbootimg
, kernel
, dtbName ? "qcom/sm8475-xiaomi-liuqin.dtb"
, ablOverlayDts ? ../dts/liuqin-abl-boot-overlay.dts
# /chosen/bootargs the kernel actually reads; ABL concatenates its own
# bootargs after it. The kernel's own DTS (patches/kernel/0001) carries a
# long debug string; the build overlays this value onto /chosen/bootargs
# with fdtoverlay before packaging, mirroring the downstream
# tools/build-liuqin-native-boot.sh cmdline-overlay step, and the final DT
# is asserted to hold exactly this. The default matches the downstream
# lib/build-bootimg.sh product default (line 44): keep_bootcon was removed
# there on purpose (lines 40-44: it keeps simplefb0 writing into the
# bootloader framebuffer all session, which a desktop compositor cannot
# draw over); in this repo it lives behind hardware.liuqin.boot.debug.
, bootargs ? "earlycon=simplefb console=drm_log console=tty0 initcall_blacklist=simplefb_driver_init,arm_smmu_init,disp_cc_sm8450_driver_init rootwait bootlog=0x9f000000,0x100000"
  # The downstream native build deliberately ships an empty header cmdline:
  # ABL concatenates its own bootargs after the header value and the kernel
  # already reads /chosen/bootargs from the DT; duplicating them in the
  # header would pass every argument twice.
, headerCmdline ? ""
, ramdisk ? null
}:

let
  # Stock ABL artifacts extracted from the operator's own device images
  # (liuqin-audit/evidence/dtbo + the stock base DTB). They are device-only
  # data: they never change for a given stock bootloader, so they are
  # imported as fixed-output paths. Point LIUQIN_STOCK_DTBO / _DTBS at the
  # tar.zst archives produced from the stock dump (see docs/PORTING-NOTES.md).
  stockDtbo = import ../data/stock-dtbo-entries.nix;
  stockBaseDtbs = import ../data/stock-base-dtbs.nix;
in
# bootargs is interpolated verbatim into a double-quoted DTS string below;
# a quote or backslash would corrupt the generated overlay (or worse).
assert lib.assertMsg (builtins.match ''.*["\\].*'' bootargs == null)
  "bootimg.nix: bootargs must not contain double quotes or backslashes";
stdenvNoCC.mkDerivation {
  pname = "liuqin-bootimg";
  version = kernel.version;
  dontUnpack = true;

  nativeBuildInputs = [ dtc gzip gnugrep gawk coreutils findutils mkbootimg zstd ];

  buildPhase = ''
    runHook preBuild

    stockDtboDir=$PWD/stock-dtbo
    stockDtbDir=$PWD/stock-dtbs
    mkdir -p "$stockDtboDir" "$stockDtbDir"
    tar --zstd -xf ${stockDtbo} -C "$stockDtboDir"
    tar --zstd -xf ${stockBaseDtbs} -C "$stockDtbDir"

    image=${kernel}/Image
    test -r "$image"
    gzip -n -9 -c "$image" > Image.gz

    base_dtb=${kernel}/dtbs/${dtbName}
    test -r "$base_dtb"

    # 1+2: ABL board-selection metadata.
    dtc -@ -I dts -O dtb -o abl-overlay.dtbo ${ablOverlayDts}
    fdtoverlay -i "$base_dtb" -o boot-0.dtb abl-overlay.dtbo

    # 1b: the kernel DTS carries the long debug bootargs; the product cmdline
    # is overlaid onto /chosen/bootargs like the downstream
    # build-liuqin-native-boot.sh cmdline-overlay does.
    {
      echo '/dts-v1/;'
      echo '/plugin/;'
      echo '/ { fragment@0 { target-path = "/chosen";'
      echo '  __overlay__ { bootargs = "${bootargs}"; }; }; };'
    } > cmdline-overlay.dts
    dtc -@ -q -I dts -O dtb -o cmdline-overlay.dtbo cmdline-overlay.dts
    fdtoverlay -i boot-0.dtb -o boot-1.dtb cmdline-overlay.dtbo

    # 3: synthesize the __symbols__ union overlay. dtc decodes with -@ so
    # __symbols__ and __fixups__ survive the round trip.
    : > symbols.list
    for overlay in $stockDtboDir/entry.*.dtb; do
      dtc -I dtb -O dts -@ "$overlay" 2>/dev/null \
        | awk '/__fixups__ \{/,/\t\};/' \
        | grep -oP '^\s*\K[A-Za-z0-9_]+(?=\s*=)' >> symbols.list
    done
    for base in $stockDtbDir/dtb-*.dtb; do
      dtc -I dtb -O dts -@ "$base" 2>/dev/null \
        | awk '/__symbols__ \{/,/\t\};/' \
        | grep -oP '^\s*\K[A-Za-z0-9_]+(?=\s*=)' >> symbols.list
    done
    sort -u symbols.list > symbols.sorted
    count=$(wc -l < symbols.sorted)
    echo "symbols exported: $count"
    # Exact contract, like the downstream --expect-symbols: the union of
    # every label the 38 stock DTBO entries reference (__fixups__) plus
    # every label the 11 stock base DTBs export (__symbols__) is exactly
    # 1744 symbols. It must stay a superset of what the downstream
    # extraction yields (44 entries / 14 base DTBs from the OS2.0.6.0
    # analysis tree, 1781 labels) because ABL force-applies the stock DTBO
    # overlay and aborts on the first fixup it cannot resolve. 1469 was the
    # single-base-DTB set: short by 275 labels (apsscc, BIG_CPU_OFF,
    # ap2mdm_active, cdsp_cvp_mem, ...).
    test "$count" = 1744

    # Input-count assertions, mirroring build-bootimg.sh:107-118. Assert
    # what this build actually consumes so a silently truncated archive
    # fails here. The base set is all 11 entries of the stock vendor_boot
    # DTB table (the ABL-selectable set), not just one.
    test "$(find "$stockDtboDir" -maxdepth 1 -name 'entry.*.dtb' | wc -l)" = 38
    test "$(find "$stockDtbDir" -maxdepth 1 -name 'dtb-*.dtb' | wc -l)" = 11
    echo "stock dtbo entries: $(ls $stockDtboDir | wc -l), base dtbs: $(ls $stockDtbDir | wc -l)"


    # The sink node plus one symbol that forces __symbols__ to exist even if
    # the mainline base ever ships one empty. The sink's phandle 0xdead0000
    # is never dereferenced: ABL only consults the __symbols__ string table
    # (label -> node path) to resolve its overlay fixups; it never walks the
    # sink node itself. Symbols the base DTB already exports keep pointing
    # at their real nodes here, whereas the downstream abl-symbols.py points
    # every symbol at the sink (see docs/PORTING-NOTES.md).
    {
      echo '/dts-v1/;'
      echo '/ {'
      echo '	liuqin-abl-overlay-sink {'
      echo '		phandle = <0xdead0000>;'
      echo '	};'
      echo '	__symbols__ {'
      while read -r sym; do
        echo "		$sym = \"/liuqin-abl-overlay-sink\";"
      done < symbols.sorted
      echo '	};'
      echo '};'
    } > symbols-add.dts

    # Decompile the merged DTB, splice the sink+symbols in before the final
    # root brace, and recompile with -@. If the base already carries a
    # __symbols__ node (fdtoverlay from an -@ overlay can create one), remove
    # it first.  Keeping real base-DTB targets would let ABL's forced stock
    # overlays mutate mainline nodes; every exported symbol must resolve to
    # the inert sink instead.
    dtc -I dtb -O dts boot-1.dtb > boot-1.dts
    awk '
      /^\t__symbols__ \{/ { skip = 1; next }
      skip && /^\t\};/ { skip = 0; next }
      !skip { print }
    ' boot-1.dts > boot-1-nosymbols.dts
    mv boot-1-nosymbols.dts boot-1.dts
    if grep -q '__symbols__ {' boot-1.dts; then
      # Merge into the existing __symbols__ block, skipping names the base
      # already exports to avoid duplicate-property errors.
      grep -A100000 '^	__symbols__ {' boot-1.dts | grep -oP '^		\K[A-Za-z0-9_]+(?= = )' | sort -u > existing.sorted
      comm -23 symbols.sorted existing.sorted > symbols.new
      {
        echo '/dts-v1/;'
        echo '/ {'
        echo '	liuqin-abl-overlay-sink {'
        echo '		phandle = <0xdead0000>;'
        echo '	};'
        echo '	__symbols__ {'
        while read -r sym; do
          echo "		$sym = \"/liuqin-abl-overlay-sink\";"
        done < symbols.new
        echo '	};'
        echo '};'
      } > symbols-add.dts
      awk -v add=symbols-add.dts '
        BEGIN { while ((getline line < add) > 0) {
                  if (line ~ /^	__symbols__/) inSym = 1
                  else if (inSym && line ~ /^	};/) inSym = 0
                  else if (inSym) extra = extra line "\n"
                } }
        /^	__symbols__ \{/ { inBlock = 1 }
        inBlock && /^	\};/ {
          printf "%s", extra
          inBlock = 0
        }
        { print }
      ' boot-1.dts > boot-2.dts
      # Add the sink node too (before the final root brace).
      awk '
        /^	liuqin-abl-overlay-sink \{/ { have = 1 }
        /^\};$/ { last = NR; lines[NR] = $0; next }
        { lines[NR] = $0 }
        END {
          for (i = 1; i <= NR; i++) {
            if (i == last && !have) print "\tliuqin-abl-overlay-sink {\n\t\tphandle = <0xdead0000>;\n\t};"
            print lines[i]
          }
        }
      ' boot-2.dts > boot-2b.dts
      mv boot-2b.dts boot-2.dts
    else
      # Append sink node and __symbols__ block before the trailing root brace.
      awk -v add=symbols-add.dts '
        BEGIN { while ((getline line < add) > 0) extra = extra "\n" line }
        /^\};$/ { last = NR; lines[NR] = $0; next }
        { lines[NR] = $0 }
        END {
          for (i = 1; i <= NR; i++) {
            if (i == last) printf "%s\n", substr(extra, 2)
            print lines[i]
          }
        }
      ' boot-1.dts > boot-2.dts
    fi
    dtc -@ -I dts -O dtb -o boot.dtb boot-2.dts

    # Verify: every requested symbol exists in the final __symbols__ (either
    # pre-existing in the base or injected pointing at the sink), and the
    # ABL metadata survived.
    dtc -I dtb -O dts boot.dtb > boot-final.dts
    missing=0
    while read -r sym; do
      grep -qP "^		\Q$sym\E = " boot-final.dts || {
        echo "missing symbol: $sym" >&2
        missing=1
      }
    done < symbols.sorted
    test "$missing" = 0
    grep -qF 'xiaomi,miboard-id = <0x10 0x00>;' boot-final.dts
    grep -qF 'qcom,board-id = <0x10008 0x00>;' boot-final.dts
    grep -qF 'qcom,msm-id = <0x213 0x10000 0x21c 0x10000 0x212 0x10000>;' boot-final.dts

    # The kernel reads /chosen/bootargs; the header cmdline is independently
    # audited. Assert the DT bootargs text.
    grep -qF 'bootargs = "${bootargs}";' boot-final.dts

    # Assert the simple-framebuffer earlycon contract survived the rewrites.
    for required in \
      'compatible = "simple-framebuffer";' \
      'reg = <0x00 0xb8000000 0x00 0x2b00000>;' \
      'width = <0x708>;' \
      'height = <0xb40>;' \
      'stride = <0x1c20>;' \
      'format = "a8r8g8b8";'; do
      grep -qF "$required" boot-final.dts || {
        echo "error: boot DTB lost the framebuffer property: $required" >&2
        exit 1
      }
    done

    # /chosen must keep the cell counts and ranges earlycon depends on
    # (build-bootimg.sh:200-210 equivalent).
    for required in \
      '#address-cells = <0x02>;' \
      '#size-cells = <0x02>;' \
      'ranges;'; do
      awk '/^\tchosen \{/,/^\t\};/' boot-final.dts | grep -qF "$required" || {
        echo "error: /chosen lost the cell counts or ranges the earlycon needs ($required)" >&2
        exit 1
      }
    done

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out

    ${lib.optionalString (ramdisk != null) ''
      cp ${ramdisk} ramdisk.cpio.gz
    ''}
    ${lib.optionalString (ramdisk == null) ''
      # An empty gzip member is a valid empty cpio archive for mkbootimg.
      printf "" | gzip -n -9 > ramdisk.cpio.gz
    ''}

    mkbootimg.py \
      --header_version 2 \
      --pagesize 4096 \
      --base 0 \
      --kernel_offset 0x00008000 \
      --ramdisk_offset 0x01000000 \
      --tags_offset 0x00000100 \
      --dtb_offset 0x01f00000 \
      --kernel Image.gz \
      --ramdisk ramdisk.cpio.gz \
      --dtb boot.dtb \
      --cmdline '${headerCmdline}' \
      --output $out/boot.img

    # 192 MiB boot partition.
    test "$(stat -c %s $out/boot.img)" -le 201326592

    # Round-trip verification, mirroring the downstream unpack checks.
    mkdir unpack
    unpack_bootimg.py --boot_img $out/boot.img --out unpack --format info > $out/boot.img.info
    cmp Image.gz unpack/kernel
    cmp boot.dtb unpack/dtb
    cmp ramdisk.cpio.gz unpack/ramdisk

    cp boot.dtb $out/sm8475-xiaomi-liuqin-abl.dtb
    runHook postInstall
  '';
}
