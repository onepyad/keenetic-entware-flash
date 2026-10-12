#!/usr/bin/env bash

get_macos_native_tools() {
    local prefix candidate
    PYTHON_BIN=""
    MKFS_EXT4=""
    DEBUGFS_BIN=""
    for prefix in /opt/homebrew /usr/local; do
        candidate="$prefix/bin/python3"
        [ -x "$candidate" ] && PYTHON_BIN="$candidate"
        candidate="$prefix/opt/e2fsprogs/sbin/mkfs.ext4"
        [ -x "$candidate" ] && MKFS_EXT4="$candidate"
        candidate="$prefix/opt/e2fsprogs/sbin/debugfs"
        [ -x "$candidate" ] && DEBUGFS_BIN="$candidate"
    done
    if [ -z "$PYTHON_BIN" ]; then PYTHON_BIN=$(command -v python3 || true); fi
    if [ -z "$MKFS_EXT4" ]; then MKFS_EXT4=$(command -v mkfs.ext4 || true); fi
    if [ -z "$DEBUGFS_BIN" ]; then DEBUGFS_BIN=$(command -v debugfs || true); fi
    if [ -z "$PYTHON_BIN" ] || [ -z "$MKFS_EXT4" ] || [ -z "$DEBUGFS_BIN" ]; then
        echo "ERROR: Для macOS без Docker нужны Homebrew, Python и e2fsprogs." >&2
        echo "Сначала выполните без sudo: bash setup-macos.sh" >&2
        return 1
    fi
}

validate_macos_native_layout() {
    [ "${PARTITION_TABLE:-mbr}" = mbr ] || {
        echo "ERROR: Native macOS preparation currently supports MBR only." >&2; return 1;
    }
    case "${SWAP_PAGE_SIZE:-4096}" in 4096|8192|16384|65536) ;; *)
        echo "ERROR: SWAP_PAGE_SIZE must be 4096, 8192, 16384 or 65536." >&2; return 1 ;;
    esac
    MAC_DISK_SIZE=$(diskutil info -plist "$DISK" | plutil -extract TotalSize raw -) || return 1
    local sector_size swap_mb
    sector_size=$(diskutil info -plist "$DISK" | plutil -extract DeviceBlockSize raw -) || return 1
    [ "$sector_size" = 512 ] || { echo "ERROR: Native MBR preparation requires 512-byte sectors." >&2; return 1; }
    swap_mb="${SWAP_SIZE:-1024}"
    MAC_SWAP_BYTES=$((10#$swap_mb * 1048576))
    if [ "$MAC_DISK_SIZE" -lt "$((MAC_SWAP_BYTES + 64 * 1048576 + 4 * 1048576))" ] || [ "$MAC_DISK_SIZE" -gt 2199023255552 ]; then
        echo "ERROR: Disk must fit swap + at least 64 MiB OPKG, and be <= 2 TiB for MBR." >&2
        return 1
    fi
}

prepare_usb_macos() {
    local raw_disk swap_part data_part swap_size filename commands readback
    raw_disk="${DISK/disk/rdisk}"
    swap_part="${raw_disk}s1"
    data_part="${raw_disk}s2"
    echo ">>> Native macOS: SWAP $((MAC_SWAP_BYTES / 1048576)) MiB + OPKG ext4."
    diskutil partitionDisk "$DISK" MBRFormat \
        'MS-DOS FAT32' SWAP "${MAC_SWAP_BYTES}B" \
        'MS-DOS FAT32' OPKG R || return 1
    # These volumes were just erased after explicit user confirmation. Spotlight
    # can hold the temporary FAT volumes open; force only this selected disk.
    if ! diskutil unmountDisk "$DISK"; then
        echo ">>> macOS удерживает новый раздел: повторяем отключение выбранной флешки." >&2
        diskutil unmountDisk force "$DISK" || return 1
    fi
    swap_size=$(diskutil info -plist "${DISK}s1" | plutil -extract TotalSize raw -) || return 1
    [ "$swap_size" = "$MAC_SWAP_BYTES" ] || {
        echo "ERROR: Actual swap partition size differs from requested size." >&2; return 1;
    }
    "$PYTHON_BIN" "$SCRIPT_DIR/lib/macos_disk.py" swap "$swap_part" \
        "$swap_size" "$ARCH" "${SWAP_PAGE_SIZE:-4096}" || return 1
    "$MKFS_EXT4" -O '^metadata_csum,^64bit,^orphan_file' -b 4096 -m 0 -L OPKG -F "$data_part" || return 1

    NATIVE_MOUNT=$(mktemp -d) || return 1 # Temporary files only; no ext4 mount on macOS.
    commands="$NATIVE_MOUNT/debugfs.txt"
    filename=$(installer_filename "$ARCH" "$INSTALLER_LANGUAGE") || return 1
    "$PYTHON_BIN" - "$commands" "$SCRIPT_DIR/scripts/S01swap" "$INSTALLER_SOURCE" "$filename" "${SKIP_ENTWARE:-0}" <<'PY' || return 1
import sys
target, script, directory, filename, skip = sys.argv[1:]
def quoted(path):
    if '\n' in path or '\r' in path:
        raise ValueError('newline in path is unsupported')
    return '"' + path.replace('\\', '\\\\').replace('"', '\\"') + '"'
lines = ['mkdir /scripts', 'write %s /scripts/S01swap' % quoted(script),
         'set_inode_field /scripts/S01swap mode 0100755']
if skip != '1':
    lines += ['mkdir /install', 'write %s /install/%s' % (quoted(directory + '/' + filename), filename)]
with open(target, 'w', encoding='utf-8') as out:
    out.write('\n'.join(lines) + '\n')
PY
    "$DEBUGFS_BIN" -w -f "$commands" "$data_part" || return 1
    # debugfs may return 0 on command errors: verify the copied files byte-for-byte.
    readback="$NATIVE_MOUNT/swap-script"
    "$DEBUGFS_BIN" -R "dump /scripts/S01swap $readback" "$data_part" || return 1
    cmp "$SCRIPT_DIR/scripts/S01swap" "$readback" || return 1
    if [ "${SKIP_ENTWARE:-0}" != 1 ]; then
        readback="$NATIVE_MOUNT/installer.tar.gz"
        "$DEBUGFS_BIN" -R "dump /install/$filename $readback" "$data_part" || return 1
        cmp "$INSTALLER_SOURCE/$filename" "$readback" || return 1
    fi
    "$PYTHON_BIN" "$SCRIPT_DIR/lib/macos_disk.py" mbr "$raw_disk" \
        "$MAC_SWAP_BYTES" "$MAC_DISK_SIZE" || return 1
    sync
    diskutil eject "$DISK" || return 1
    rm -f "$commands" "$NATIVE_MOUNT/swap-script" "$NATIVE_MOUNT/installer.tar.gz"
    rmdir "$NATIVE_MOUNT"
    NATIVE_MOUNT=""
    echo "Готово: раздел 1 — Linux SWAP, раздел 2 — OPKG ext4 с установщиком."
    echo "Вставьте флешку в роутер и выберите накопитель в настройках OPKG."
    echo "После установки Entware включите автозапуск SWAP:"
    echo "cp /opt/scripts/S01swap /opt/etc/init.d/S01swap"
    echo "chmod +x /opt/etc/init.d/S01swap"
    echo "/opt/etc/init.d/S01swap start"
}
