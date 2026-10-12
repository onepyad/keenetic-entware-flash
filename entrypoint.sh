#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Keenetic Entware Flash — USB flash drive preparation for Keenetic Entware
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/entware.sh
source "${ENTWARE_LIB:-$SCRIPT_DIR/lib/entware.sh}"
TARGET="${TARGET:-/dev/target}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/usb}"
SWAP_SCRIPT="${SWAP_SCRIPT:-/opt/scripts/S01swap}"
INSTALLER_DIR="${INSTALLER_DIR:-/opt/entware-installers}"
MOUNTED=0
LOOP_DEVICE=""
CLEANUP_LOOP=0
KPARTX_DEVICE=""

# Defaults (overridable via env)
ARCH="${ARCH:-}"
INSTALLER_LANGUAGE="${INSTALLER_LANGUAGE:-ru}"
SWAP_SIZE="${SWAP_SIZE:-1024}"
PARTITION_TABLE="${PARTITION_TABLE:-mbr}"
SKIP_ENTWARE="${SKIP_ENTWARE:-0}"
FORCE="${FORCE:-0}"

# ============================================================================
# Help
# ============================================================================
show_help() {
    cat <<'HELP'
Keenetic Entware Flash — USB flash drive preparation for Keenetic Entware

Usage (Linux):
  docker run --rm -it --privileged \
    -v /dev/sdX:/dev/target \
    keenetic-entware-flash

Usage (macOS):
  # 1. Create disk image from USB
  sudo dd if=/dev/rdiskN of=/tmp/usb.img bs=1m
  # 2. Process in container
  docker run --rm -it --privileged \
    -v /tmp/usb.img:/dev/target \
    keenetic-entware-flash
  # 3. Write image back to USB
  sudo dd if=/tmp/usb.img of=/dev/rdiskN bs=1m

Environment variables:
  MODEL             Exact model, e.g. KN-1811 (see run.sh --list-platforms)
  ARCH              Router architecture: mipsel, mips, aarch64 (no default)
  INSTALLER_LANGUAGE  ru (default) or en
  SWAP_SIZE         Swap partition size in MB (default: 1024)
  PARTITION_TABLE   Partition table type: mbr (default) or gpt
  SKIP_ENTWARE      Skip Entware download: 0 (default) or 1
  FORCE             Skip confirmation prompt: 0 (default) or 1

Examples of verified models:
  MIPSEL   KN-1810, KN-3810
  MIPS     KN-2410, KN-3610
  AARCH64  KN-1811, KN-3811, KN-2710

Examples:
  # Linux — direct block device
  docker run --rm -it --privileged -v /dev/sdb:/dev/target keenetic-entware-flash

  # macOS — via disk image
  docker run --rm -it --privileged -v /tmp/usb.img:/dev/target keenetic-entware-flash

  # AArch64 with GPT and 512MB swap
  docker run --rm -it --privileged \
    -e ARCH=aarch64 -e SWAP_SIZE=512 -e PARTITION_TABLE=gpt \
    -v /dev/sdb:/dev/target keenetic-entware-flash
HELP
    exit 0
}

# ============================================================================
# Cleanup on exit
# ============================================================================
cleanup() {
    if [ "$MOUNTED" = "1" ]; then
        umount "$MOUNT_POINT" 2>/dev/null || true
    fi
    if [ -n "$KPARTX_DEVICE" ]; then
        kpartx -dv "$KPARTX_DEVICE" 2>/dev/null || true
    fi
    if [ "$CLEANUP_LOOP" = "1" ] && [ -n "$LOOP_DEVICE" ]; then
        losetup -d "$LOOP_DEVICE" 2>/dev/null || true
    fi
}
trap cleanup EXIT

validate_configuration() {
    [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]] && [ "${#SWAP_SIZE}" -le 7 ] && [ "$SWAP_SIZE" -ge 2 ] || {
        echo "ERROR: SWAP_SIZE must be an integer >= 2 MiB." >&2; return 1;
    }
    SWAP_SIZE=$((10#$SWAP_SIZE))
    case "$PARTITION_TABLE" in mbr|gpt) ;; *) echo "ERROR: PARTITION_TABLE must be mbr or gpt." >&2; return 1 ;; esac
    case "$SKIP_ENTWARE:$FORCE" in 0:0|0:1|1:0|1:1) ;; *) echo "ERROR: SKIP_ENTWARE and FORCE must be 0 or 1." >&2; return 1 ;; esac
    if [ "$SKIP_ENTWARE" = "1" ] && [ -z "$ARCH" ] && [ -z "${MODEL:-}" ]; then
        ARCH=mipsel # Formatting only: no CPU-dependent files downloaded.
    else
        select_platform || return $?
    fi
    [ -f "$SWAP_SCRIPT" ] || { echo "ERROR: SWAP script not found: $SWAP_SCRIPT" >&2; return 1; }
}

require_tools() {
    local cmd
    for cmd in parted blockdev dd partprobe kpartx mkswap mkfs.ext4 mount umount sync tar losetup; do
        command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: Required utility is missing: $cmd" >&2; return 1; }
    done
}

validate_disk_size() {
    local bytes
    bytes=$(blockdev --getsize64 "$DEVICE") || return 1
    if [ "$bytes" -lt "$(((SWAP_SIZE + 68) * 1048576))" ]; then
        echo "ERROR: Disk is too small for SWAP_SIZE=$SWAP_SIZE and at least 64 MiB of data." >&2
        return 1
    fi
}

# ============================================================================
# Device setup
# ============================================================================
setup_device() {
    if [ ! -e "$TARGET" ]; then
        echo "ERROR: $TARGET not found."
        echo ""
        echo "Mount your USB device into the container:"
        echo ""
        echo "  Linux:  docker run --rm -it --privileged -v /dev/sdX:/dev/target keenetic-entware-flash"
        echo ""
        echo "  macOS:  1) sudo dd if=/dev/rdiskN of=/tmp/usb.img bs=1m"
        echo "          2) docker run --rm -it --privileged -v /tmp/usb.img:/dev/target keenetic-entware-flash"
        echo "          3) sudo dd if=/tmp/usb.img of=/dev/rdiskN bs=1m"
        exit 1
    fi

    if [ -b "$TARGET" ]; then
        # Linux: direct block device
        DEVICE="$TARGET"
        echo "Mode: direct block device"
    elif [ -f "$TARGET" ]; then
        # macOS: disk image file → attach via losetup
        echo "Mode: disk image file (macOS)"
        LOOP_DEVICE=$(losetup --find --show --partscan "$TARGET")
        CLEANUP_LOOP=1
        DEVICE="$LOOP_DEVICE"
        echo "Loop device: $LOOP_DEVICE"
    else
        echo "ERROR: $TARGET is neither a block device nor a regular file."
        echo ""
        echo "On macOS, Docker cannot pass block devices directly."
        echo "Use a disk image instead:"
        echo "  1) sudo dd if=/dev/rdiskN of=/tmp/usb.img bs=1m"
        echo "  2) docker run --rm -it --privileged -v /tmp/usb.img:/dev/target keenetic-entware-flash"
        echo "  3) sudo dd if=/tmp/usb.img of=/dev/rdiskN bs=1m"
        exit 1
    fi
}

# ============================================================================
# Display info
# ============================================================================
show_disk_info() {
    echo "============================================"
    echo " Keenetic Entware Flash — USB Preparation Tool"
    echo "============================================"
    echo ""
    echo "Device: $DEVICE"

    local size_bytes
    size_bytes=$(blockdev --getsize64 "$DEVICE" 2>/dev/null || echo "unknown")
    if [ "$size_bytes" != "unknown" ]; then
        local size_gb
        size_gb=$(awk "BEGIN {printf \"%.1f\", $size_bytes / 1073741824}")
        echo "Size:   ${size_gb} GB (${size_bytes} bytes)"
    fi

    echo ""
    echo "Current partition table:"
    parted -s "$DEVICE" print 2>/dev/null || echo "  (no partition table or unreadable)"
    echo ""
    echo "Parameters:"
    echo "  Architecture:      $ARCH ($(arch_to_path "$ARCH"))"
    echo "  Swap size:         ${SWAP_SIZE} MB"
    echo "  Partition table:   ${PARTITION_TABLE}"
    echo "  Entware download:  $([ "$SKIP_ENTWARE" = "1" ] && echo "skip" || echo "yes")"
    echo ""
}

confirm() {
    if [ "$FORCE" = "1" ]; then
        echo "[FORCE mode] Skipping confirmation."
        return 0
    fi

    echo "WARNING: ALL DATA WILL BE DESTROYED!"
    echo ""
    read -r -p "Continue? [y/N]: " answer
    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) echo "Aborted."; exit 0 ;;
    esac
}

# ============================================================================
# Partitioning & formatting
# ============================================================================
partition_disk() {
    echo ""
    echo ">>> Creating ${PARTITION_TABLE^^} partition table..."

    # Wipe existing partition table
    dd if=/dev/zero of="$DEVICE" bs=1M count=1 conv=notrunc 2>/dev/null

    local label_type
    if [ "$PARTITION_TABLE" = "gpt" ]; then
        label_type="gpt"
    else
        label_type="msdos"
    fi

    parted -s "$DEVICE" mklabel "$label_type"

    echo ">>> Creating swap partition (${SWAP_SIZE} MB)..."
    local swap_end=$((SWAP_SIZE + 1))
    parted -s "$DEVICE" mkpart primary linux-swap 1MiB "${swap_end}MiB"

    echo ">>> Creating ext4 partition (remaining space)..."
    parted -s "$DEVICE" mkpart primary ext4 "${swap_end}MiB" 100%

    # Wait for partition devices to appear
    sleep 1
    partprobe "$DEVICE" 2>/dev/null || true
    sleep 1

    # Determine partition device names
    local part1 part2
    if [ -e "${DEVICE}p1" ]; then
        part1="${DEVICE}p1"
        part2="${DEVICE}p2"
    elif [ -e "${DEVICE}1" ]; then
        part1="${DEVICE}1"
        part2="${DEVICE}2"
    else
        # In Docker, partition nodes may not appear automatically — use kpartx
        echo ">>> Partition nodes not found, using kpartx..."
        kpartx -av "$DEVICE"
        sleep 1
        local loop_name
        loop_name=$(basename "$DEVICE")
        part1="/dev/mapper/${loop_name}p1"
        part2="/dev/mapper/${loop_name}p2"
        KPARTX_DEVICE="$DEVICE"
        if [ ! -e "$part1" ]; then
            echo "ERROR: Partition devices not found after kpartx."
            echo "Tried: $part1, $part2"
            exit 1
        fi
    fi

    echo ">>> Formatting swap ($part1)..."
    mkswap -L SWAP "$part1"

    echo ">>> Formatting ext4 ($part2)..."
    # Feature flags are tuned for Keenetic's 32-bit, kernel-3.4 ext4 driver:
    #   ^metadata_csum  modern checksums the old kernel does not understand
    #   ^64bit          INCOMPAT feature enabled by default in new mke2fs; a
    #                   kernel without 64bit support REFUSES to mount the fs
    #                   (only needed beyond 16 TB anyway), so the data partition
    #                   silently never appears on the router.
    #   uninit_bg       marks empty block groups uninitialized so their inode
    #                   tables are never read; this is what makes the fast
    #                   "skip empty blocks" write-back in run.sh safe on a USB
    #                   that already held data.
    # -b 4096 -m 0 matches Keenetic's documented mkfs command (max usable space).
    mkfs.ext4 -O ^metadata_csum,^64bit,uninit_bg -b 4096 -m 0 -L OPKG -F "$part2"

    echo ">>> Partitioning complete."
    echo ""
    parted -s "$DEVICE" print
}

# ============================================================================
# Find ext4 partition device
# ============================================================================
find_ext4_partition() {
    local loop_name
    loop_name=$(basename "$DEVICE")
    if [ -e "${DEVICE}p2" ]; then
        echo "${DEVICE}p2"
    elif [ -e "${DEVICE}2" ]; then
        echo "${DEVICE}2"
    elif [ -e "/dev/mapper/${loop_name}p2" ]; then
        echo "/dev/mapper/${loop_name}p2"
    else
        echo ""
    fi
}

# ============================================================================
# Entware installation & scripts
# ============================================================================
install_entware() {
    local part2
    part2=$(find_ext4_partition)
    if [ -z "$part2" ]; then
        echo "ERROR: ext4 partition not found."
        exit 1
    fi

    echo ""
    echo ">>> Mounting ext4 partition..."
    mkdir -p "$MOUNT_POINT"
    mount "$part2" "$MOUNT_POINT"
    MOUNTED=1

    # Download Entware installer
    if [ "$SKIP_ENTWARE" = "1" ]; then
        echo ">>> Skipping Entware download (SKIP_ENTWARE=1)."
    else
        local filename
        filename=$(installer_filename "$ARCH" "$INSTALLER_LANGUAGE")
        mkdir -p "${MOUNT_POINT}/install"
        # The archive has been validated before formatting.
        cp "$INSTALLER_DIR/$filename" "${MOUNT_POINT}/install/${filename}"
    fi

    # Copy SWAP init script (always, regardless of SKIP_ENTWARE)
    echo ">>> Copying SWAP init script..."
    mkdir -p "${MOUNT_POINT}/scripts"
    cp "$SWAP_SCRIPT" "${MOUNT_POINT}/scripts/S01swap"
    chmod +x "${MOUNT_POINT}/scripts/S01swap"
    echo ">>> SWAP script saved to /scripts/S01swap on the USB drive."

    echo ">>> Unmounting..."
    umount "$MOUNT_POINT"
    MOUNTED=0
}

# ============================================================================
# Success message
# ============================================================================
show_success() {
    echo ""
    echo "============================================"
    echo " SUCCESS! Image is ready."
    echo "============================================"
    echo ""
    echo "Partition layout:"
    echo "  Partition 1: SWAP (${SWAP_SIZE} MB)"
    echo "  Partition 2: OPKG ext4 (data + Entware)"
    echo ""
    if [ "$SKIP_ENTWARE" != "1" ]; then
        echo "Entware architecture: $ARCH ($(arch_to_path "$ARCH"))"
        echo ""
    fi
    echo "SWAP auto-start script: /scripts/S01swap"
    echo "  After OPKG installation, copy it to enable auto-start:"
    echo "  cp /opt/scripts/S01swap /opt/etc/init.d/S01swap"
    echo ""
}

# ============================================================================
# Main
# ============================================================================
main() {
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        show_help
    fi

    validate_configuration
    require_tools
    # Download and validate before formatting, including direct Docker usage.
    if [ "$SKIP_ENTWARE" != "1" ]; then
        local filename
        filename=$(installer_filename "$ARCH" "$INSTALLER_LANGUAGE")
        if [ ! -s "$INSTALLER_DIR/$filename" ]; then
            download_installer "$ARCH" "$INSTALLER_LANGUAGE" "$INSTALLER_DIR"
        fi
        tar -tzf "$INSTALLER_DIR/$filename" >/dev/null
    fi
    setup_device
    validate_disk_size
    show_disk_info
    confirm
    partition_disk
    install_entware
    sync
    show_success
}

if [ "${ENTRYPOINT_SH_TESTING:-0}" != "1" ]; then
    main "$@"
fi
