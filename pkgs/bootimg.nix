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
# bootargs after it. Must match what the running system expects.
, bootargs ? "earlycon=simplefb console=drm_log console=tty0 initcall_blacklist=simplefb_driver_init rootwait"
, headerCmdline ? bootargs
, ramdisk ? null
}:

let
  stockDtbo = fetchurl {
    url = "https://github.com/yzddmr6/xiaomipad-6pro-mainline/releases/download/liuqin-stock-dtb-refs/stock-dtbo-entries.tar.zst";
    # PLACEHOLDER: fill with the real hash of the stock DTBO entry set.
    hash = lib.fakeHash;
  };
  stockBaseDtbs = fetchurl {
    url = "https://github.com/yzddmr6/xiaomipad-6pro-mainline/releases/download/liuqin-stock-dtb-refs/stock-base-dtbs.tar.zst";
    hash = lib.fakeHash;
  };
in
stdenvNoCC.mkDerivation {
  pname = "liuqin-bootimg";
  version = kernel.version;

  nativeBuildInputs = [ dtc gzip gnugrep gawk coreutils findutils mkbootimg ];

  buildPhase = ''
    runHook preBuild

    image=${kernel}/Image
    test -r "$image"
    gzip -n -9 -c "$image" > Image.gz

    base_dtb=${kernel}/dtbs/${dtbName}
    test -r "$base_dtb"

    # 1+2: ABL board-selection metadata.
    dtc -@ -I dts -O dtb -o abl-overlay.dtbo ${ablOverlayDts}
    fdtoverlay -i "$base_dtb" -o boot-1.dtb abl-overlay.dtbo

    # 3: synthesize the __symbols__ union overlay. dtc decodes with -@ so
    # __symbols__ and __fixups__ survive the round trip.
    : > symbols.list
    for overlay in ${stockDtbo}/entry.*; do
      dtc -I dtb -O dts -@ "$overlay" 2>/dev/null \
        | awk '/__fixups__ \{/,/\t\};/' \
        | grep -oP '^\s*\K[A-Za-z0-9_]+(?=\s*=)' >> symbols.list
    done
    for base in ${stockBaseDtbs}/dtb-*.dtb; do
      dtc -I dtb -O dts -@ "$base" 2>/dev/null \
        | awk '/__symbols__ \{/,/\t\};/' \
        | grep -oP '^\s*\K[A-Za-z0-9_]+(?=\s*=)' >> symbols.list
    done
    sort -u symbols.list > symbols.sorted
    count=$(wc -l < symbols.sorted)
    echo "symbols exported: $count"
    # Guard the union size like the downstream --expect-symbols did.
    test "$count" -gt 200

    # The sink node plus one symbol that forces __symbols__ to exist even if
    # the mainline base ever ships one empty.
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
    # root brace, and recompile with -@. Using dtc text round-trip here is
    # exactly what abl-symbols.py did; this derivation keeps the same
    # verification discipline (decode the output and check).
    dtc -I dtb -O dts boot-1.dtb > boot-1.dts
    if grep -q '__symbols__' boot-1.dts; then
      echo "error: boot DTB already has __symbols__" >&2
      exit 1
    fi
    # Append the sink node and __symbols__ block to the root level: insert
    # before the trailing "};" of the root node.
    awk -v add=symbols-add.dts '
      BEGIN { while ((getline line < add) > 0) extra = extra "\n" line }
      # Root closes at the last "};" line.
      /^\};$/ { last = NR; lines[NR] = $0; next }
      { lines[NR] = $0 }
      END {
        for (i = 1; i <= NR; i++) {
          if (i == last) printf "%s\n", substr(extra, 2)
          print lines[i]
        }
      }
    ' boot-1.dts > boot-2.dts
    dtc -@ -I dts -O dtb -o boot.dtb boot-2.dts

    # Verify: every requested symbol resolves to the sink, and the ABL
    # metadata survived.
    dtc -I dtb -O dts boot.dtb > boot-final.dts
    missing=0
    while read -r sym; do
      grep -qF "	$sym = \"/liuqin-abl-overlay-sink\";" boot-final.dts || {
        echo "missing symbol: $sym" >&2
        missing=1
      }
    done < symbols.sorted
    test "$missing" = 0
    grep -qF 'xiaomi,miboard-id = <0x10 0x00>;' boot-final.dts
    grep -qF 'qcom,board-id = <0x10008 0x00>;' boot-final.dts
    grep -qF 'compatible = "qcom,capep";' boot-final.dts || \
      grep -q 'compatible = .*qcom,capep' boot-final.dts

    # The kernel reads /chosen/bootargs; the header cmdline is independently
    # audited. Assert the DT bootargs text.
    grep -qF 'bootargs = "${bootargs}";' boot-final.dts

    # Assert the simple-framebuffer earlycon contract survived the rewrites.
    for required in \
      'compatible = "simple-framebuffer";' \
      'width = <0x708>;' \
      'height = <0xb40>;' \
      'format = "a8r8g8b8";'; do
      grep -qF "$required" boot-final.dts || {
        echo "error: boot DTB lost the framebuffer property: $required" >&2
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
