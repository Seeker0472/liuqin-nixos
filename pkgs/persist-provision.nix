# SPDX-License-Identifier: MIT
#
# Provision liuqin's per-device data from the factory persist partition (sda21)
# read-only: WLAN MAC, Bluetooth address, CS35L41 per-channel calibration and
# the SSC sensor registry. Everything here is device-unique, so none of it can
# live in the Nix store or the repository.
#
# Wired into units by modules/liuqin/sensors.nix, which supplies the system
# layout as flags; the fail-closed checks (exact byte counts, a >100-file
# registry floor, a malformed identity is fatal) follow the downstream
# provision-liuqin-from-persist.sh.
#
# `--persist-source DIR` skips the mount entirely, so the whole command can be
# run against a fixture tree without a persist partition.
{ writeShellApplication
, coreutils
, findutils
, gnused
, util-linux
}:

writeShellApplication {
  name = "liuqin-persist-provision";

  runtimeInputs = [ coreutils findutils gnused util-linux ];

  # SC2094 flags the SHA256SUMS pipeline as reading and writing one file: the
  # redirect creates the file, and `find` then walks the directory *excluding*
  # it by name. The data flow is deliberate; there is nothing to fix.
  excludeShellChecks = [ "SC2094" ];

  text = ''
    persist_part=/dev/disk/by-partlabel/persist
    persist_source=
    private_dir=/var/lib/liuqin-private
    sensor_dir=/var/lib/liuqin-sensors
    firmware_dir=/var/lib/firmware
    ssc_config=
    owner=root
    group=root
    registry_user=fastrpc
    registry_group=fastrpc

    usage() {
      cat >&2 <<'EOF'
usage: liuqin-persist-provision [--persist-source DIR] [--persist-part DEV]
                                [--private-dir DIR] [--sensor-dir DIR]
                                [--firmware-dir DIR] [--ssc-config DIR]
                                [--owner USER] [--group GROUP]
                                [--registry-user USER] [--registry-group GROUP]

--persist-source takes an already-mounted persist tree and skips the mount;
--ssc-config is the store directory carrying sensors/sns_reg_version.
EOF
      exit 2
    }

    while [ "$#" -gt 0 ]; do
      case $1 in
        --persist-source|--persist-part|--private-dir|--sensor-dir|--firmware-dir|--ssc-config|--owner|--group|--registry-user|--registry-group)
          if [ "$#" -lt 2 ]; then
            usage
          fi
          case $1 in
            --persist-source) persist_source=$2 ;;
            --persist-part) persist_part=$2 ;;
            --private-dir) private_dir=$2 ;;
            --sensor-dir) sensor_dir=$2 ;;
            --firmware-dir) firmware_dir=$2 ;;
            --ssc-config) ssc_config=$2 ;;
            --owner) owner=$2 ;;
            --group) group=$2 ;;
            --registry-user) registry_user=$2 ;;
            --registry-group) registry_group=$2 ;;
          esac
          shift 2
          ;;
        *) usage ;;
      esac
    done

    mnt=$persist_source
    mounted=
    stage=
    cleanup() {
      [ -z "$stage" ] || rm -rf "$stage"
      if [ -n "$mounted" ]; then
        umount "$mounted" 2>/dev/null || true
        rmdir "$mounted" 2>/dev/null || true
      fi
    }
    trap cleanup EXIT

    if [ -z "$mnt" ]; then
      # Downstream semantics: a missing persist partition is a hard failure,
      # not a skip - audio, WLAN and BT identities would silently run
      # uncalibrated/factory otherwise.
      [ -b "$persist_part" ] || {
        echo "liuqin-persist-provision: $persist_part is absent" >&2
        exit 1
      }
      mnt=$(mktemp -d)
      mount -o ro,nodev,nosuid,noexec "$persist_part" "$mnt"
      mounted=$mnt
    else
      [ -d "$mnt" ] || {
        echo "liuqin-persist-provision: $mnt is not a directory" >&2
        exit 1
      }
    fi

    install -d -m 0700 -o "$owner" -g "$group" "$private_dir"

    # The DSP registry mount is writable runtime state. Keep the vendor
    # configuration in the Nix store, but seed the mutable siblings that the
    # firmware removes, creates and updates during regeneration.
    install -d -m 0750 -o "$registry_user" -g "$registry_group" "$sensor_dir"
    if [ ! -e "$sensor_dir/sns_reg_version" ]; then
      if [ -n "$ssc_config" ] && [ -f "$ssc_config/sensors/sns_reg_version" ]; then
        install -m 0640 -o "$registry_user" -g "$registry_group" \
          "$ssc_config/sensors/sns_reg_version" "$sensor_dir/sns_reg_version"
      else
        echo "liuqin-persist-provision: no sns_reg_version seeded (--ssc-config missing or incomplete)" >&2
      fi
    fi
    for mutable in sensors_list.txt file1 file2; do
      if [ ! -e "$sensor_dir/$mutable" ]; then
        install -m 0640 -o "$registry_user" -g "$registry_group" /dev/null \
          "$sensor_dir/$mutable"
      fi
    done

    # Fail closed when the persist payload set is incomplete.
    [ -f "$mnt/wlan/wlan_mac.bin" ]
    [ -f "$mnt/bluetooth/.bt_nv.bin" ]
    [ -f "$mnt/audio/crus_calr.bin" ]
    [ -d "$mnt/sensors/registry/registry" ]

    # WLAN MAC: text "wlan0=AABBCCDDEEFF" -> colon-separated.
    raw=$(cat "$mnt/wlan/wlan_mac.bin")
    hex=$(printf '%s' "$raw" | sed -n 's/^wlan0=\([0-9A-Fa-f]\{12\}\).*/\1/p' | head -1)
    [ -n "$hex" ] || {
      echo "liuqin-persist-provision: wlan_mac.bin does not carry a wlan0= entry" >&2
      exit 1
    }
    printf '%s\n' "$(printf '%s' "$hex" | sed 's/../&:/g; s/:$//' | tr 'A-F' 'a-f')" \
      > "$private_dir/wlan-mac"
    chown "$owner:$group" "$private_dir/wlan-mac"
    chmod 0600 "$private_dir/wlan-mac"

    # Bluetooth address: 6 raw bytes in order -> colon-separated text.
    bt_hex=$(od -An -tx1 -N6 "$mnt/bluetooth/.bt_nv.bin" | tr -d ' \n')
    [ ''${#bt_hex} -eq 12 ] || {
      echo "liuqin-persist-provision: .bt_nv.bin is not 6 bytes: $bt_hex" >&2
      exit 1
    }
    printf '%s\n' "$(printf '%s' "$bt_hex" | sed 's/../&:/g; s/:$//')" \
      > "$private_dir/bluetooth-address"
    chown "$owner:$group" "$private_dir/bluetooth-address"
    chmod 0600 "$private_dir/bluetooth-address"

    # CS35L41 per-channel calibration (4x4 bytes, order TL TR BL BR).
    # The kernel requests cirrus/cs35l41-liuqin-<ch>-calr.bin through the
    # firmware loader; the blobs land in <firmware-dir>/cirrus/ (with the
    # exact 16-byte check).  <firmware-dir> is one of the lowerdirs of the
    # firmware overlay that liuqin-firmware-path mounts (pkgs/firmware-path.nix)
    # because per-device data cannot live in the store.
    calr_size=$(wc -c < "$mnt/audio/crus_calr.bin" | tr -d ' ')
    [ "$calr_size" = 16 ]
    install -d -m 0755 "$firmware_dir/cirrus"
    i=0
    for ch in TL TR BL BR; do
      dd if="$mnt/audio/crus_calr.bin" bs=4 skip=$i count=1 \
        of="$firmware_dir/cirrus/cs35l41-liuqin-$ch-calr.bin" status=none
      chown "$owner:$group" "$firmware_dir/cirrus/cs35l41-liuqin-$ch-calr.bin"
      chmod 0600 "$firmware_dir/cirrus/cs35l41-liuqin-$ch-calr.bin"
      i=$((i + 1))
    done

    # SSC sensor registry (fastrpc-readable); refuse implausibly small sets
    # like the downstream >100-file floor. Stage the complete directory, then
    # exchange it with the active directory in one renameat2 operation so
    # readers never see a half-imported registry.
    stage=$(mktemp -d "$sensor_dir/.registry.XXXXXX")
    chown "$registry_user:$registry_group" "$stage"
    chmod 0750 "$stage"
    count=0
    for f in "$mnt/sensors/registry/registry/"*; do
      [ -f "$f" ] && [ ! -L "$f" ] || continue
      name=''${f##*/}
      [ -n "$name" ] || exit 1
      case $name in .*|*/*) exit 1 ;; esac
      install -m 0640 -o "$registry_user" -g "$registry_group" "$f" "$stage/$name"
      count=$((count + 1))
    done
    [ "$count" -gt 100 ] || {
      echo "liuqin-persist-provision: suspiciously few registry files: $count" >&2
      exit 1
    }
    (cd "$stage" && find . -maxdepth 1 -type f ! -name SHA256SUMS \
      -printf '%P\0' | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS)
    chown "$registry_user:$registry_group" "$stage/SHA256SUMS"
    chmod 0640 "$stage/SHA256SUMS"
    if [ -e "$sensor_dir/registry" ] || [ -L "$sensor_dir/registry" ]; then
      [ -d "$sensor_dir/registry" ] && [ ! -L "$sensor_dir/registry" ] || exit 1
      # GNU coreutils' --exchange maps to renameat2(RENAME_EXCHANGE). A
      # filesystem without that primitive fails closed and leaves the old
      # active directory untouched.
      mv --exchange --no-target-directory "$stage" "$sensor_dir/registry"
      # The old directory now occupies $stage; cleanup removes it only after
      # the new directory has become active.
    else
      mv "$stage" "$sensor_dir/registry"
      stage=
    fi
    if [ ! -e "$sensor_dir/registry/temp.json" ]; then
      install -m 0640 -o "$registry_user" -g "$registry_group" /dev/null \
        "$sensor_dir/registry/temp.json"
    fi
  '';
}
