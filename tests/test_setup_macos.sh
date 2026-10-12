#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_SETUP_DIR=$(mktemp -d)
export TEST_SETUP_DIR BREW_SEARCH_PATHS=""
trap 'rm -rf "$TEST_SETUP_DIR"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
uname() { echo Darwin; }
id() { echo "${TEST_UID:-501}"; }
command() {
    if [ "${1:-}" = -v ] && [ "$2" = brew ]; then
        [ -e "$TEST_SETUP_DIR/brew-ready" ] || return 1
        echo brew
        return 0
    fi
    builtin command "$@"
}
curl() {
    local destination=""
    while [ "$#" -gt 0 ]; do
        if [ "$1" = -o ]; then destination="$2"; shift; fi
        shift
    done
    touch "$TEST_SETUP_DIR/installer-downloaded"
    printf 'touch "%s/brew-ready"\n' "$TEST_SETUP_DIR" > "$destination"
}
brew() {
    case "$1" in
        shellenv) echo 'export TEST_BREW_SHELL_READY=1' ;;
        install)
            [ "${TEST_BREW_SHELL_READY:-0}" = 1 ] || return 1
            printf '%s\n' "$*" > "$TEST_SETUP_DIR/packages"
            ;;
        *) return 1 ;;
    esac
}
export -f uname id command curl brew

# Missing Homebrew: official installer must run before dependency installation.
bash "$REPO_DIR/setup-macos.sh" > "$TEST_SETUP_DIR/missing.log"
[ -e "$TEST_SETUP_DIR/installer-downloaded" ] || fail "missing brew did not trigger installer"
[ "$(cat "$TEST_SETUP_DIR/packages")" = 'install git python e2fsprogs' ] || fail "wrong prerequisites installed"

# Existing Homebrew: do not download/reinstall it.
rm -f "$TEST_SETUP_DIR/installer-downloaded" "$TEST_SETUP_DIR/packages"
bash "$REPO_DIR/setup-macos.sh" > "$TEST_SETUP_DIR/existing.log"
[ ! -e "$TEST_SETUP_DIR/installer-downloaded" ] || fail "existing Homebrew was reinstalled"
[ -e "$TEST_SETUP_DIR/packages" ] || fail "dependencies not installed"

# Homebrew must not run as root.
rm -f "$TEST_SETUP_DIR/packages"
if TEST_UID=0 bash "$REPO_DIR/setup-macos.sh" > "$TEST_SETUP_DIR/root.log" 2>&1; then fail "root setup allowed"; fi
[ ! -e "$TEST_SETUP_DIR/packages" ] || fail "root setup reached brew"
echo "macOS setup tests passed"
