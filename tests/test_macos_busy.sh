#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/lib/macos.sh"
TMP_TEST=$(mktemp -d)
trap 'rm -rf "$TMP_TEST"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

check_busy() (
    DISK=/dev/disk7
    trace="$TMP_TEST/$1"
    attempts="$trace.attempts"
    echo 0 > "$attempts"
    diskutil() {
        [ "$1" = unmountDisk ] || fail "unexpected diskutil command"
        if [ "$2" = force ]; then
            [ "$3" = "$DISK" ] || fail "wrong force target"
            echo force >> "$trace"
            return "${FORCE_STATUS:-0}"
        fi
        [ "$2" = "$DISK" ] || fail "wrong unmount target"
        local count
        count=$(cat "$attempts")
        echo "$((count + 1))" > "$attempts"
        echo unmount >> "$trace"
        if [ "$count" -gt 0 ] && [ "${RELEASED:-0}" = 1 ]; then return 0; fi
        echo "Unmount was dissented by PID ${OCCUPANT_PID:-12345} (/mock/mdsync)"
        echo 'Dissenter parent PPID 1 (/sbin/launchd)'
        return 1
    }
    ps() {
        [ "$*" = '-p 12345 -o comm=' ] || fail "unexpected process inspection"
        printf '%s\n' "${PROCESS_PATH:-/mock/mdsync}"
    }
    kill() {
        [ "$*" = '-TERM 12345' ] || fail "wrong process killed"
        echo terminate >> "$trace"
    }
    sleep() { :; }
    if [ "${FORCE_STATUS:-0}" = 0 ]; then
        unmount_prepared_usb_macos >/dev/null 2>&1 || fail "unmount failed"
    else
        if unmount_prepared_usb_macos >/dev/null 2>&1; then fail "force failure suppressed"; fi
    fi
    [ "$(cat "$trace")" = "$EXPECTED" ] || fail "unexpected actions: $(cat "$trace")"
)

EXPECTED=$'unmount\nterminate\nunmount' RELEASED=1 check_busy released
EXPECTED=$'unmount\nterminate\nunmount\nforce' check_busy still-busy
EXPECTED=$'unmount\nunmount\nforce' PROCESS_PATH=/mock/other check_busy reused-pid
EXPECTED=$'unmount\nunmount\nforce' OCCUPANT_PID=1 check_busy protected-pid
EXPECTED=$'unmount\nterminate\nunmount\nforce' FORCE_STATUS=1 check_busy force-failed
echo 'macOS busy process tests passed'
