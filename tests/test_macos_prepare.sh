#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_TEST=$(mktemp -d)
trap 'rm -rf "$TMP_TEST"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

test_preparation() (
    source "$REPO_DIR/lib/entware.sh"
    source "$REPO_DIR/lib/macos.sh"
    SCRIPT_DIR="$REPO_DIR" DISK=/dev/disk7 ARCH=aarch64 INSTALLER_LANGUAGE=ru
    MAC_SWAP_BYTES=1073741824 MAC_DISK_SIZE=17179869184 SKIP_ENTWARE=0
    INSTALLER_SOURCE="$TMP_TEST/installers"
    mkdir -p "$INSTALLER_SOURCE"
    printf 'fixture' > "$INSTALLER_SOURCE/aarch64-installer.tar.gz"
    PYTHON_BIN=mock_python MKFS_EXT4=mock_mkfs DEBUGFS_BIN=mock_debugfs
    TRACE="$TMP_TEST/trace-${FAIL_STEP:-success}"
    step() {
        printf '%s\n' "$1" >> "$TRACE"
        [ "${FAIL_STEP:-}" != "$1" ]
    }
    diskutil() {
        case "$1" in
            partitionDisk)
                [ "$*" = "partitionDisk /dev/disk7 MBRFormat MS-DOS FAT32 SWAP 1073741824B MS-DOS FAT32 OPKG R" ] || fail "wrong swap partition size"
                step partition ;;
            unmountDisk) step unmount ;;
            info) [ "$3" = /dev/disk7s1 ] || fail "wrong partition queried"; echo '<unused/>' ;;
            eject) step eject ;;
            *) fail "unexpected diskutil invocation" ;;
        esac
    }
    plutil() { cat >/dev/null; echo 1073741824; }
    mock_python() {
        if [ "$1" = - ]; then
            command python3 "$@"
        elif [ "$2" = swap ]; then
            [ "$3" = /dev/rdisk7s1 ] && [ "$4" = 1073741824 ] || fail "wrong swap device/size"
            step swap
        elif [ "$2" = mbr ]; then
            [ "$3" = /dev/rdisk7 ] || fail "wrong MBR device"
            step mbr
        else fail "unexpected Python invocation"; fi
    }
    mock_mkfs() { [ "${!#}" = /dev/rdisk7s2 ] || fail "wrong ext4 target"; step ext4; }
    mock_debugfs() {
        if [ "$1" = -w ]; then
            step files || return 1
            grep -q 'mkdir /install' "$3" || fail "installer directory not created"
            grep -q 'set_inode_field /scripts/S01swap mode 0100755' "$3" || fail "swap script is not executable"
        else
            local command_text="$2" destination
            destination="${command_text##* }"
            case "$command_text" in
                'dump /scripts/S01swap '*) cp "$SCRIPT_DIR/scripts/S01swap" "$destination" ;;
                'dump /install/aarch64-installer.tar.gz '*) cp "$INSTALLER_SOURCE/aarch64-installer.tar.gz" "$destination" ;;
                *) fail "unexpected debugfs readback" ;;
            esac
        fi
    }
    sync() { step sync; }
    if [ -z "${FAIL_STEP:-}" ]; then
        prepare_usb_macos >/dev/null
        [ "$(cat "$TRACE")" = $'partition\nunmount\nswap\next4\nfiles\nmbr\nsync\neject' ] || fail "incorrect preparation order"
        [ -f "$INSTALLER_SOURCE/aarch64-installer.tar.gz" ] || fail "user installer was removed"
    else
        if prepare_usb_macos >/dev/null 2>&1; then fail "failure suppressed: $FAIL_STEP"; fi
        [ "$(tail -1 "$TRACE")" = "$FAIL_STEP" ] || fail "preparation continued after $FAIL_STEP"
        if [ -n "${NATIVE_MOUNT:-}" ]; then rm -rf "$NATIVE_MOUNT"; fi
    fi
)

test_preparation
for failure in partition unmount swap ext4 files mbr eject; do
    FAIL_STEP="$failure" test_preparation
done
echo "native macOS preparation tests passed"
