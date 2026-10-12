#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_TEST=$(mktemp -d)
trap 'rm -rf "$TMP_TEST"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
SWAP_SCRIPT_TESTING=1 source "$REPO_DIR/scripts/S01swap"
find_swap_device() { echo /dev/fake; }
mkswap() { fail "swap start attempted to format a partition"; }

printf 'Filename Type Size Used Priority\n/dev/fake partition 1048572 0 -2\n' > "$TMP_TEST/swaps"
SWAPS_FILE="$TMP_TEST/swaps"
swapon() { fail "already-active swap was enabled again"; }
start >/dev/null

printf 'Filename Type Size Used Priority\n' > "$TMP_TEST/swaps"
swapon() { return 1; }
if start >/dev/null 2>&1; then fail "swapon error was suppressed"; fi

printf 'Filename Type Size Used Priority\n/dev/fake partition 1048572 0 -2\n/dev/other partition 20 0 -3\n' > "$TMP_TEST/swaps"
swapoff() {
    [ "$#" = 1 ] && [ "$1" = /dev/fake ] || fail "stop affected another swap area"
}
stop >/dev/null
echo "SWAP activation tests passed"
