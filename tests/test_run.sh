#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_TEST=$(mktemp -d)
trap 'rm -rf "$TMP_TEST"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Each case gets a clean subshell: no real Docker, root or disk access.
test_no_docker_linux() (
    RUN_SH_TESTING=1 source "$REPO_DIR/run.sh"
    trap - EXIT
    command() {
        if [ "${1:-}" = -v ]; then
            case "$2" in docker) return 1 ;; parted|blockdev|lsblk|dd|partprobe|kpartx|mkswap|mkfs.ext4|mount|umount|sync) return 0 ;; esac
        fi
        builtin command "$@"
    }
    BACKEND=auto OS=Linux ARCH=mipsel
    choose_backend >/dev/null
    [ "$BACKEND" = native ] || fail "Docker absence did not select native Linux"
)

test_unavailable_daemon() (
    RUN_SH_TESTING=1 source "$REPO_DIR/run.sh"
    trap - EXIT
    docker() { return 1; }
    BACKEND=docker OS=Linux ARCH=mipsel
    if choose_backend >"$TMP_TEST/daemon.log" 2>&1; then fail "unavailable daemon accepted"; fi
    grep -q 'daemon is unavailable' "$TMP_TEST/daemon.log" || fail "daemon failure not explained"
    [ "$BACKEND" = docker ] || fail "explicit Docker request switched backend"
)

test_missing_dependencies_before_device_selection() (
    RUN_SH_TESTING=1 source "$REPO_DIR/run.sh"
    trap - EXIT
    command() {
        if [ "${1:-}" = -v ]; then
            case "$2" in docker|parted) return 1 ;; esac
        fi
        builtin command "$@"
    }
    uname() { echo Linux; }
    select_disk_linux() { touch "$TMP_TEST/device-touched"; return 1; }
    if main --model NC-1812 >"$TMP_TEST/deps.log" 2>&1; then fail "missing dependencies accepted"; fi
    [ ! -e "$TMP_TEST/device-touched" ] || fail "disk selection reached before preflight failure"
    grep -q 'sudo apt install' "$TMP_TEST/deps.log" || fail "dependency installation guidance missing"
)

test_no_docker_macos() (
    RUN_SH_TESTING=1 source "$REPO_DIR/run.sh"
    trap - EXIT
    command() {
        if [ "${1:-}" = -v ] && [ "$2" = docker ]; then return 1; fi
        builtin command "$@"
    }
    uname() { echo Darwin; }
    select_disk_macos() { touch "$TMP_TEST/macos-device-touched"; return 1; }
    if main --backend docker --model NC-1013 >"$TMP_TEST/macos.log" 2>&1; then fail "missing macOS Docker accepted"; fi
    [ ! -e "$TMP_TEST/macos-device-touched" ] || fail "macOS device accessed without Docker"
    grep -q 'brew install --cask docker' "$TMP_TEST/macos.log" || fail "Docker installation guidance missing"
    grep -q -- '--download-installer' "$TMP_TEST/macos.log" || fail "download alternative missing"
)

test_download_without_docker_or_root() (
    RUN_SH_TESTING=1 source "$REPO_DIR/run.sh"
    trap - EXIT
    choose_backend() { fail "download asked for Docker"; }
    id() { fail "download asked for root"; }
    select_disk_linux() { fail "download selected a device"; }
    download_installer() { printf '%s %s %s\n' "$@" > "$TMP_TEST/download.args"; }
    main --model NC-1913 --installer-language en --download-installer "$TMP_TEST/download"
    [ "$(cat "$TMP_TEST/download.args")" = "mipsel en $TMP_TEST/download" ] || fail "wrong download selected"
)

test_invalid_partition_parameters() (
    ENTRYPOINT_SH_TESTING=1 SWAP_SCRIPT="$REPO_DIR/scripts/S01swap" source "$REPO_DIR/entrypoint.sh"
    trap - EXIT
    ARCH=mipsel SKIP_ENTWARE=0 FORCE=0
    SWAP_SIZE=bad
    if validate_configuration >/dev/null 2>&1; then fail "invalid swap accepted"; fi
    SWAP_SIZE=1024 PARTITION_TABLE=bad
    if validate_configuration >/dev/null 2>&1; then fail "invalid partition table accepted"; fi
    SWAP_SIZE=01024 PARTITION_TABLE=mbr SWAP_SCRIPT="$REPO_DIR/scripts/S01swap"
    validate_configuration >/dev/null
    [ "$SWAP_SIZE" = 1024 ] || fail "leading-zero swap not normalized"
)

test_declining_prevents_macos_write() (
    RUN_SH_TESTING=1 source "$REPO_DIR/run.sh"
    trap - EXIT
    SKIP_ENTWARE=1 FORCE=0
    uname() { echo Darwin; }
    id() { echo 0; }
    choose_backend() { BACKEND=docker; }
    validate_target() { return 0; }
    python3() { fail "image writer ran despite cancellation"; }
    docker() { fail "Docker operation ran despite cancellation"; }
    diskutil() { fail "macOS disk operation ran despite cancellation"; }
    main --model NC-1812 /dev/disk4 <<< no
)

test_native_dispatch() (
    RUN_SH_TESTING=1 source "$REPO_DIR/run.sh"
    trap - EXIT
    SKIP_ENTWARE=1 FORCE=1
    uname() { echo Linux; }
    id() { echo 0; }
    choose_backend() { BACKEND=native; }
    validate_target() { return 0; }
    docker() { fail "native branch invoked Docker"; }
    bash() {
        [ "$TARGET" = /dev/fake ] || fail "native target was not forwarded"
        [ "$ARCH" = aarch64 ] || fail "native architecture was not forwarded"
        [ "$SWAP_SCRIPT" = "$REPO_DIR/scripts/S01swap" ] || fail "native swap script missing"
        [ "$FORCE" = 1 ] || fail "native confirmation not forwarded"
        [ "$1" = "$REPO_DIR/entrypoint.sh" ] || fail "wrong native entrypoint"
        touch "$TMP_TEST/native-dispatched"
    }
    main --model NC-1812 /dev/fake
    [ -e "$TMP_TEST/native-dispatched" ] || fail "native entrypoint not invoked"
    cleanup
)

test_native_macos_dispatch() (
    RUN_SH_TESTING=1 source "$REPO_DIR/run.sh"
    trap - EXIT
    SKIP_ENTWARE=1 FORCE=1
    uname() { echo Darwin; }
    id() { echo 0; }
    choose_backend() { BACKEND=native; }
    validate_target() { return 0; }
    validate_macos_native_layout() { touch "$TMP_TEST/native-macos-validated"; }
    prepare_usb_macos() {
        [ -e "$TMP_TEST/native-macos-validated" ] || fail "native macOS layout not validated"
        touch "$TMP_TEST/native-macos-dispatched"
    }
    docker() { fail "native macOS invoked Docker"; }
    main --backend native --model NC-1812 /dev/disk7
    [ -e "$TMP_TEST/native-macos-dispatched" ] || fail "native macOS was not dispatched"
)

test_no_docker_linux
test_unavailable_daemon
test_missing_dependencies_before_device_selection
test_no_docker_macos
test_download_without_docker_or_root
test_invalid_partition_parameters
test_declining_prevents_macos_write
test_native_dispatch
test_native_macos_dispatch
echo "launcher preflight tests passed"
