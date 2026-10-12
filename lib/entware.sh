#!/usr/bin/env bash
# Shared by the launcher, downloader and container. Compatible with Bash 3.2.

arch_to_path() {
    case "$1" in
        mipsel) echo mipselsf-k3.4 ;;
        mips) echo mipssf-k3.4 ;;
        aarch64) echo aarch64-k3.10 ;;
        *) echo "ERROR: Unsupported router architecture '$1'. Use mipsel, mips or aarch64." >&2; return 1 ;;
    esac
}

installer_filename() {
    arch_to_path "$1" >/dev/null || return 1
    case "${2:-ru}" in
        ru) printf '%s-installer.tar.gz\n' "$1" ;;
        en) printf 'EN_%s-installer.tar.gz\n' "$1" ;;
        *) echo "ERROR: INSTALLER_LANGUAGE must be ru or en." >&2; return 1 ;;
    esac
}

installer_url() {
    local platform filename
    platform=$(arch_to_path "$1") || return 1
    filename=$(installer_filename "$1" "${2:-ru}") || return 1
    printf 'https://bin.entware.net/%s/installer/%s\n' "$platform" "$filename"
}

# Exact model IDs only: the same product name can have different CPUs.
# Source and verification date: docs/platforms.md (2026-10-12).
model_to_arch() {
    local model
    model=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')
    case "$model" in
        KN-1010|KN-1011|KN-1810|KN-1910|KN-1912|KN-1913|KN-2610|KN-2310|KN-2311|KN-2910|KN-3810|NC-1913) echo mipsel ;;
        KN-2010|KN-2110|KN-2510|KN-2410|KN-2112|KN-3610) echo mips ;;
        KN-2710|KN-1811|KN-1812|KN-1012|KN-3811|KN-3812|KN-2312|KN-4110) echo aarch64 ;;
        NC-1012|NC-1013|NC-1812|NC-2312|NC-3611|NC-3811|NC-3812|NC-4110|NC-4210) echo aarch64 ;;
        NC-1221|NC-1721)
            echo "ERROR: $model supports USB modems, not USB storage/OPKG. This USB installer is not applicable." >&2; return 1 ;;
        *) echo "ERROR: No verified platform for '$1'. Check the exact KN/NC model in the manufacturer's manual, then specify --arch." >&2; return 1 ;;
    esac
}

list_platforms() {
    cat <<'PLATFORMS'
Router platform   Entware repository   Verified model IDs
mipsel            mipselsf-k3.4        KN-1010, KN-1011, KN-1810, KN-1910, KN-1912, KN-1913, KN-2610, KN-2310, KN-2311, KN-2910, KN-3810
mips              mipssf-k3.4          KN-2010, KN-2110, KN-2510, KN-2410, KN-2112, KN-3610
aarch64           aarch64-k3.10        KN-2710, KN-1811, KN-1812, KN-1012, KN-3811, KN-3812, KN-2312, KN-4110

Netcraze models from the official catalogue and OPKG manuals:
mipsel:  Viva NC-1913
aarch64: Giga NC-1012/NC-1013, Ultra NC-1812, Hopper NC-3811,
         Hopper SE NC-3812, Hopper 4G+ NC-2312, Hopper DSL NC-3611,
         Hero 5G NC-4110, Titan SE NC-4210
Launcher NC-1221 and Carrier NC-1721: USB modem only; no USB OPKG.

Use the exact KN/NC model on the router label, not its marketing name.
Unknown models require a verified --arch; the PC's CPU is unrelated.
Other Entware platforms (ARMv5, ARMv7, x86, x64) have generic installers,
not the Keenetic USB installers used by this tool.
PLATFORMS
    local arch
    for arch in mipsel mips aarch64; do
        printf '\n%s (RU): %s\n' "$arch" "$(installer_url "$arch" ru)"
        printf '%s (EN): %s\n' "$arch" "$(installer_url "$arch" en)"
    done
    echo ""
    echo "Official model reference: https://support.keenetic.com/hero-5g/kn-4110/en/69806-installation-of-the-asterisk-ip-pbx-opkg-package.html"
    echo "Netcraze catalogue: https://netcraze.ru/ru/products"
    echo "Netcraze platforms: https://support.netcraze.ru/viva/nc-1913/ru/69806-installation-of-the-asterisk-ip-pbx-opkg-package.html"
}

select_platform() {
    local choice resolved
    if [ -n "${MODEL:-}" ]; then
        resolved=$(model_to_arch "$MODEL") || return 1
        if [ -n "${ARCH:-}" ] && [ "$ARCH" != "$resolved" ]; then
            echo "ERROR: $MODEL requires $resolved, but ARCH=$ARCH was supplied." >&2
            return 1
        fi
        ARCH="$resolved"
    elif [ -z "${ARCH:-}" ]; then
        if [ ! -t 0 ]; then
            echo "ERROR: Specify --model KN-xxxx/NC-xxxx or --arch mipsel|mips|aarch64 for non-interactive use." >&2
            return 1
        fi
        list_platforms
        echo ""
        echo "Select: 1) mipsel  2) mips  3) aarch64  0) cancel"
        while true; do
            read -r -p "Enter exact model (KN-xxxx/NC-xxxx) or platform number: " choice || return 1
            case "$choice" in
                0) return 2 ;;
                1) ARCH=mipsel; break ;;
                2) ARCH=mips; break ;;
                3) ARCH=aarch64; break ;;
                *)
                    if resolved=$(model_to_arch "$choice"); then
                        MODEL="$choice"; ARCH="$resolved"; break
                    fi
                    ;;
            esac
        done
    fi
    arch_to_path "$ARCH" >/dev/null || return 1
    installer_filename "$ARCH" "${INSTALLER_LANGUAGE:-ru}" >/dev/null || return 1
    export ARCH INSTALLER_LANGUAGE
    echo "Router platform: $ARCH${MODEL:+ ($MODEL)}"
    echo "Official installer: $(installer_url "$ARCH" "${INSTALLER_LANGUAGE:-ru}")"
}

download_installer() (
    local arch="$1" language="$2" directory="$3" filename url temporary
    filename=$(installer_filename "$arch" "$language") || return 1
    url=$(installer_url "$arch" "$language") || return 1
    command -v tar >/dev/null 2>&1 || { echo "ERROR: tar is required to validate installers." >&2; return 1; }
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        echo "ERROR: Install curl or wget to download from bin.entware.net." >&2
        return 1
    fi
    mkdir -p "$directory" || return 1
    if [ -e "$directory/$filename" ]; then
        echo "ERROR: $directory/$filename already exists; choose another directory." >&2
        return 1
    fi
    temporary=$(mktemp "$directory/.entware-download-XXXXXX") || return 1
    trap 'rm -f "$temporary"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    echo ">>> Downloading $url"
    if command -v curl >/dev/null 2>&1; then
        if ! curl --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 180 --speed-limit 1024 --speed-time 20 --retry 2 -o "$temporary" "$url"; then
            rm -f "$temporary"; return 1
        fi
    elif ! wget --timeout=30 --tries=3 -O "$temporary" "$url"; then
        rm -f "$temporary"; return 1
    fi
    if [ ! -s "$temporary" ] || ! tar -tzf "$temporary" >/dev/null 2>&1; then
        echo "ERROR: Download is not a valid tar.gz installer." >&2
        rm -f "$temporary"; return 1
    fi
    mv "$temporary" "$directory/$filename" || { rm -f "$temporary"; return 1; }
    echo "Installer saved: $directory/$filename"
)
