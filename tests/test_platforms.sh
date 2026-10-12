#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/lib/entware.sh"
TMP_TEST=$(mktemp -d)
trap 'rm -rf "$TMP_TEST"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "got '$1', expected '$2'"; }

assert_eq "$(model_to_arch KN-3810)" mipsel
assert_eq "$(model_to_arch kn-3811)" aarch64
assert_eq "$(model_to_arch KN-2110)" mips
assert_eq "$(model_to_arch NC-1913)" mipsel
for model in NC-1012 NC-1013 NC-1812 NC-3811 NC-3812 NC-2312 NC-3611 NC-4110 NC-4210; do
    assert_eq "$(model_to_arch "$model")" aarch64
done
if model_to_arch KN-9999 >/dev/null 2>&1; then fail "unknown model accepted"; fi
if model_to_arch NC-1221 >/dev/null 2>&1; then fail "USB modem-only model accepted"; fi
if model_to_arch NC-1721 >/dev/null 2>&1; then fail "USB modem-only model accepted"; fi
if model_to_arch NC-2410 >/dev/null 2>&1; then fail "unverified NC-to-KN alias accepted"; fi
if arch_to_path x86_64 >/dev/null 2>&1; then fail "PC architecture accepted as router platform"; fi
if installer_filename mipsel xx >/dev/null 2>&1; then fail "invalid installer language accepted"; fi

assert_eq "$(installer_url mipsel ru)" https://bin.entware.net/mipselsf-k3.4/installer/mipsel-installer.tar.gz
assert_eq "$(installer_url mips en)" https://bin.entware.net/mipssf-k3.4/installer/EN_mips-installer.tar.gz
assert_eq "$(installer_url aarch64 en)" https://bin.entware.net/aarch64-k3.10/installer/EN_aarch64-installer.tar.gz
if ( MODEL=NC-1812 ARCH=mipsel select_platform ) >/dev/null 2>&1; then fail "conflicting architecture accepted"; fi
if ( unset MODEL ARCH; select_platform </dev/null ) >/dev/null 2>&1; then fail "missing platform silently defaulted"; fi

# Mock HTTP only; exercise real archive validation and filesystem publication.
mkdir -p "$TMP_TEST/fixture"
printf 'fixture\n' > "$TMP_TEST/fixture/doinstall"
tar -czf "$TMP_TEST/good.tar.gz" -C "$TMP_TEST/fixture" doinstall
curl() {
    local dest=""
    while [ "$#" -gt 0 ]; do
        if [ "$1" = -o ]; then dest="$2"; shift; fi
        shift
    done
    case "${HTTP_RESULT:-ok}" in
        ok) cp "$TMP_TEST/good.tar.gz" "$dest" ;;
        html) printf '<html>Unavailable</html>\n' > "$dest" ;;
        failure) printf partial > "$dest"; return 22 ;;
    esac
}
download_installer aarch64 en "$TMP_TEST/success" >/dev/null
tar -tzf "$TMP_TEST/success/EN_aarch64-installer.tar.gz" >/dev/null || fail "valid download missing"
if download_installer aarch64 en "$TMP_TEST/success" >/dev/null 2>&1; then fail "existing download overwritten"; fi
for result in html failure; do
    if HTTP_RESULT="$result" download_installer mips ru "$TMP_TEST/$result" >/dev/null 2>&1; then
        fail "bad download accepted: $result"
    fi
    [ -z "$(ls -A "$TMP_TEST/$result")" ] || fail "partial file remains after $result"
done
echo "platform and download tests passed"
