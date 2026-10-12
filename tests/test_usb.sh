#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/lib/usb.sh"
TMP_TEST=$(mktemp -d)
trap 'rm -rf "$TMP_TEST"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Confirmations and listings are mocked. No real devices are read or written.
test_single_after_prompt() (
    wait_for_usb() { touch "$TMP_TEST/prompted"; }
    list_usb_devices() {
        [ -e "$TMP_TEST/prompted" ] || fail "scan happened before disconnect prompt"
        echo /dev/disk7
    }
    describe_usb_device() { [ "$2" = /dev/disk7 ] || fail "wrong descriptor"; }
    auto_select_usb Darwin >/dev/null 2>&1
    [ "$DISK" = /dev/disk7 ] || fail "single device not selected"
)

test_zero_and_multiple_retry() (
    waits=0
    wait_for_usb() { waits=$((waits + 1)); }
    list_usb_devices() {
        case "$waits" in
            1) return 0 ;;
            2) printf '/dev/disk7\n/dev/disk8\n' ;;
            3) echo /dev/disk8 ;;
            *) fail "unexpected retry" ;;
        esac
    }
    describe_usb_device() { [ "$waits" = 3 ] || fail "ambiguous device selected"; }
    auto_select_usb Darwin >"$TMP_TEST/retries.out" 2>"$TMP_TEST/retries.log"
    [ "$waits" = 3 ] && [ "$DISK" = /dev/disk8 ] || fail "rescan did not select sole remaining device"
    [ ! -s "$TMP_TEST/retries.out" ] || fail "status messages contaminated stdout"
)

test_cancel() (
    wait_for_usb() { return 2; }
    list_usb_devices() { fail "scan ran after cancellation"; }
    rc=0
    auto_select_usb Darwin >/dev/null 2>&1 || rc=$?
    [ "$rc" = 2 ] || fail "cancellation did not propagate"
)

test_parsers() (
    diskutil() {
        cat <<'DISKS'
/dev/disk7 (external, physical):
   0: FDisk_partition_scheme *16.0 GB disk7
   1: DOS_FAT_32 TEST 16.0 GB disk7s1
/dev/disk8 (external, physical):
DISKS
    }
    lsblk() {
        printf '/dev/sda disk 0 sata\n/dev/sdb disk 0 usb\n/dev/sdc disk 1 \n/dev/nvme0n1 disk 0 nvme\n'
    }
    [ "$(list_usb_devices Darwin)" = $'/dev/disk7\n/dev/disk8' ] || fail "macOS parser included partitions"
    [ "$(list_usb_devices Linux)" = $'/dev/sdb\n/dev/sdc' ] || fail "Linux USB/removable parser failed"
)

test_detect_only_stdout() (
    RUN_SH_TESTING=1 source "$REPO_DIR/run.sh"
    trap - EXIT
    uname() { echo Darwin; }
    wait_for_usb() { return 0; }
    list_usb_devices() { echo /dev/disk7; }
    describe_usb_device() { echo 'Example USB, 16 GB' >&2; }
    choose_backend() { fail "detection required a backend"; }
    select_platform() { fail "detection required a router platform"; }
    id() { fail "detection required root"; }
    [ "$(main --detect-usb 2>"$TMP_TEST/detect.log")" = /dev/disk7 ] || fail "detection did not output only a device path"
)

test_single_after_prompt
test_zero_and_multiple_retry
test_cancel
test_parsers
test_detect_only_stdout
echo "USB auto-selection tests passed"
