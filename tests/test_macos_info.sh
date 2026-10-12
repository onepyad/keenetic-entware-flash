#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_TEST=$(mktemp -d)
trap 'rm -rf "$TMP_TEST"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

test_plist_validation() (
    RUN_SH_TESTING=1 source "$REPO_DIR/run.sh"
    trap - EXIT
    OS=Darwin DISK=/dev/disk4
    FIELD=WholeDisk WHOLE=true INTERNAL=false
    diskutil() {
        [ "$*" = 'info -plist /dev/disk4' ] || fail "unexpected device operation: $*"
        printf '<?xml version="1.0"?><plist version="1.0"><dict>\n'
        if [ -n "$FIELD" ]; then printf '<key>%s</key><%s/>\n' "$FIELD" "$WHOLE"; fi
        printf '<key>Internal</key><%s/>\n' "$INTERNAL"
        printf '<key>TotalSize</key><integer>15502147584</integer>\n'
        printf '<key>DeviceBlockSize</key><integer>512</integer>\n'
        printf '</dict></plist>\n'
    }
    # Real plist parsing; mirror only plutil's CLI/boolean rendering on non-Mac hosts.
    plutil() {
        python3 -c 'import plistlib,sys; value=plistlib.load(sys.stdin.buffer)[sys.argv[1]]; print(str(value).lower() if isinstance(value,bool) else value)' "$2"
    }
    validate_target || fail "WholeDisk plist was rejected"
    FIELD=Whole
    validate_target || fail "legacy Whole field was rejected"
    FIELD=WholeDisk INTERNAL=true
    if validate_target >/dev/null 2>&1; then fail "internal disk was accepted"; fi
    INTERNAL=false WHOLE=false
    if validate_target >/dev/null 2>&1; then fail "partition was accepted"; fi
    FIELD="" WHOLE=true
    if validate_target >/dev/null 2>&1; then fail "missing whole-disk identity was accepted"; fi

    FIELD=WholeDisk
    uname() { echo Darwin; }
    id() { echo 0; }
    choose_backend() { BACKEND=native; }
    prepare_usb_macos() { fail "formatting ran after cancellation"; }
    SKIP_ENTWARE=1 FORCE=0
    main --backend native --model NC-1812 /dev/disk4 <<< no > "$TMP_TEST/main.log"
    grep -q Aborted "$TMP_TEST/main.log" || fail "normal WholeDisk preflight did not reach confirmation"
)

test_plist_validation
echo "macOS diskutil plist tests passed"
