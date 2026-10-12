#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Keenetic Entware Flash — one-command launcher
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/entware.sh"
source "$SCRIPT_DIR/lib/usb.sh"
source "$SCRIPT_DIR/lib/macos.sh"
REMOTE_IMAGE="${REMOTE_IMAGE:-ghcr.io/onepyad/keenetic-entware-flash:main}"
LOCAL_IMAGE="keenetic-entware-flash"
IMAGE=""
TMP_IMG=""
INSTALLER_TMP=""
INSTALLER_SOURCE=""
NATIVE_MOUNT=""

show_help() {
    cat <<'HELP'
Keenetic Entware Flash — one-command USB preparation

Usage:
  sudo ./run.sh [--model KN-xxxx/NC-xxxx | --arch ARCH] [/dev/diskN | /dev/sdX]
  ./run.sh --list-platforms
  ./run.sh --detect-usb
  ./run.sh --model KN-1811 --download-installer [directory]

Options:
  --model KN/NC-xxxx      Exact router model (MODEL env also accepted)
  --arch ARCH             mipsel, mips or aarch64; never the PC architecture
  --installer-language    ru (default) or en
  --backend MODE          auto (default), docker or native (Linux/macOS)
  --installer-dir DIR    Use an already downloaded, validated installer
  --download-installer    Download only; no Docker, root or disk required
  --list-platforms       Show verified models and official download links
  --detect-usb           Detect the only attached external USB; print its path, no writes
  -h, --help             Show this help

Environment: MODEL, ARCH, INSTALLER_LANGUAGE, BACKEND, SWAP_SIZE,
PARTITION_TABLE, SKIP_ENTWARE, FORCE. Native Linux needs parted, e2fsprogs,
util-linux and kpartx. Native macOS needs Python + e2fsprogs: bash setup-macos.sh.

HELP
    exit 0
}

# Automatic selection is allowed only when exactly one candidate remains.
select_disk_macos() { auto_select_usb Darwin; }
select_disk_linux() { auto_select_usb Linux; }

cleanup() {
    if [ -n "$TMP_IMG" ] && [ -f "$TMP_IMG" ]; then
        echo ">>> Cleaning up temporary image..."
        rm -f "$TMP_IMG"
    fi
    if [ -n "$INSTALLER_TMP" ] && [ -d "$INSTALLER_TMP" ]; then
        rm -rf "$INSTALLER_TMP"
    fi
    if [ -n "$NATIVE_MOUNT" ] && [ -d "$NATIVE_MOUNT" ]; then
        rmdir "$NATIVE_MOUNT" 2>/dev/null || true
    fi
}
trap cleanup EXIT

choose_backend() {
    case "$BACKEND" in auto|docker|native) ;; *) echo "ERROR: --backend must be auto, docker or native." >&2; return 1 ;; esac
    if [ "$BACKEND" != native ] && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        BACKEND=docker
        return 0
    fi
    if [ "$BACKEND" = auto ] && [ "$OS" = Darwin ]; then
        echo ">>> Docker unavailable; using native macOS tools."
        BACKEND=native
    fi
    if [ "$BACKEND" = native ] && [ "$OS" = Darwin ]; then
        get_macos_native_tools || return 1
        return 0
    fi
    if [ "$BACKEND" = auto ] && [ "$OS" = Linux ]; then
        echo ">>> Docker unavailable; using native Linux tools."
        BACKEND=native
    fi
    if [ "$BACKEND" = native ] && [ "$OS" = Linux ]; then
        local cmd missing=""
        for cmd in parted blockdev lsblk dd partprobe kpartx mkswap mkfs.ext4 mount umount sync; do
            command -v "$cmd" >/dev/null 2>&1 || missing="$missing $cmd"
        done
        if [ -n "$missing" ]; then
            echo "ERROR: Missing native Linux tools:$missing" >&2
            echo "Debian/Ubuntu: sudo apt install parted e2fsprogs util-linux kpartx curl" >&2
            echo "Or install Docker Engine: https://docs.docker.com/engine/install/" >&2
            return 1
        fi
        return 0
    fi
    if [ "$BACKEND" = native ]; then
        echo "ERROR: Automatic native flashing supports Linux and macOS." >&2
    elif command -v docker >/dev/null 2>&1; then
        echo "ERROR: Docker is installed, but its daemon is unavailable or access is denied." >&2
    else
        echo "ERROR: Docker is not installed." >&2
    fi
    if [ "$OS" = Darwin ]; then
        echo "Install Docker Desktop: brew install --cask docker" >&2
        echo "Then start Docker Desktop and wait until docker info succeeds." >&2
    else
        echo "Docker installation: https://docs.docker.com/engine/install/" >&2
    fi
    echo "Installer-only download requires no Docker: ./run.sh --arch $ARCH --download-installer" >&2
    return 1
}

validate_target() {
    if [ "$OS" = Linux ]; then
        [ -b "$DISK" ] || { echo "ERROR: $DISK is not a block device." >&2; return 1; }
        [ "$(lsblk -dnro TYPE "$DISK")" = disk ] || { echo "ERROR: Select a whole disk, not a partition." >&2; return 1; }
        [ "$(lsblk -dnro RO "$DISK")" = 0 ] || { echo "ERROR: Device is read-only." >&2; return 1; }
        local mounts
        mounts=$(lsblk -nr -o MOUNTPOINT "$DISK") || return 1
        if [ -n "$(printf '%s' "$mounts" | tr -d '[:space:]')" ]; then
            echo "ERROR: $DISK has mounted partitions or active swap. Unmount them before flashing." >&2
            return 1
        fi
    else
        [[ "$DISK" =~ ^/dev/disk[0-9]+$ ]] || { echo "ERROR: Use a whole disk such as /dev/disk4." >&2; return 1; }
        local whole internal info
        info=$(diskutil info -plist "$DISK") || return 1
        whole=$(printf '%s\n' "$info" | plutil -extract WholeDisk raw - 2>/dev/null) ||
            whole=$(printf '%s\n' "$info" | plutil -extract Whole raw - 2>/dev/null) || {
                echo "ERROR: diskutil did not identify whether $DISK is a whole disk. No data was written." >&2
                return 1
            }
        internal=$(printf '%s\n' "$info" | plutil -extract Internal raw - 2>/dev/null) || {
            echo "ERROR: diskutil did not identify whether $DISK is external. No data was written." >&2
            return 1
        }
        [ "$whole" = true ] && [ "$internal" = false ] || {
            echo "ERROR: Select an external whole disk." >&2; return 1;
        }
    fi
}

confirm_target() {
    echo "WARNING: ALL DATA on $DISK will be destroyed. Router platform: $ARCH."
    if [ "${FORCE:-0}" != 1 ]; then
        local answer
        read -r -p "Type yes to continue: " answer || return 1
        [ "$answer" = yes ] || { echo "Aborted."; return 2; }
    fi
}

main() {
    local download_only=0 download_dir=installers detect_only=0 installer_dir=""
    DISK=""
    BACKEND="${BACKEND:-auto}"
    INSTALLER_LANGUAGE="${INSTALLER_LANGUAGE:-ru}"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help) show_help ;;
            --list-platforms) list_platforms; return 0 ;;
            --detect-usb) detect_only=1; shift ;;
            --model|--arch|--installer-language|--backend|--installer-dir)
                [ "$#" -ge 2 ] || { echo "ERROR: $1 requires a value." >&2; return 1; }
                case "$1" in
                    --model) MODEL="$2" ;;
                    --arch) ARCH="$2" ;;
                    --installer-language) INSTALLER_LANGUAGE="$2" ;;
                    --backend) BACKEND="$2" ;;
                    --installer-dir) installer_dir="$2" ;;
                esac
                shift 2
                ;;
            --download-installer)
                download_only=1; shift
                if [ "$#" -gt 0 ] && [[ "$1" != -* ]] && [[ "$1" != /dev/* ]]; then
                    download_dir="$1"; shift
                fi
                ;;
            /dev/*)
                [ -z "$DISK" ] || { echo "ERROR: Only one target device is allowed." >&2; return 1; }
                DISK="$1"; shift
                ;;
            *) echo "ERROR: Unknown argument: $1" >&2; return 1 ;;
        esac
    done
    if [ "$detect_only" = 1 ]; then
        if [ "$download_only" = 1 ] || [ -n "$DISK" ]; then
            echo "ERROR: --detect-usb cannot be combined with a device or download-only mode." >&2; return 1
        fi
        auto_select_usb "$(uname -s)" || return $?
        printf '%s\n' "$DISK"
        return 0
    fi
    if [ "$download_only" = 1 ] && [ -n "$DISK" ]; then
        echo "ERROR: Download-only mode does not take a device." >&2; return 1
    fi
    if [ "${SKIP_ENTWARE:-0}" = 1 ] && [ "$download_only" = 0 ] && [ -z "${ARCH:-}" ] && [ -z "${MODEL:-}" ]; then
        ARCH=mipsel # Formatting only; no architecture-specific download.
    else
        local rc=0
        select_platform || rc=$?
        [ "$rc" = 2 ] && return 0
        [ "$rc" = 0 ] || return "$rc"
    fi
    if [ "$download_only" = 1 ]; then
        download_installer "$ARCH" "$INSTALLER_LANGUAGE" "$download_dir"
        return $?
    fi
    OS="$(uname -s)"
    case "$OS" in Linux|Darwin) ;; *) echo "ERROR: Flashing supports Linux and macOS. Use --download-installer on other hosts." >&2; return 1 ;; esac
    choose_backend || return 1
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: Flashing requires root. Use sudo; download-only mode does not." >&2; return 1
    fi
    if [ "$OS" = Darwin ] && [ "$BACKEND" = docker ] && ! command -v python3 >/dev/null 2>&1; then
        echo "ERROR: Python 3 is required for macOS image creation and writing. Install: brew install python" >&2; return 1
    fi
    if [ -z "$DISK" ]; then
        local selection_rc=0
        if [ "$OS" = Darwin ]; then
            select_disk_macos || selection_rc=$?
        else
            select_disk_linux || selection_rc=$?
        fi
        [ "$selection_rc" = 2 ] && return 0
        [ "$selection_rc" = 0 ] || return "$selection_rc"
    fi
    validate_target || return 1
    # Shared validation runs before downloads, confirmation and any disk writes.
    (
        export ENTRYPOINT_SH_TESTING=1 SWAP_SCRIPT="$SCRIPT_DIR/scripts/S01swap"
        source "$SCRIPT_DIR/entrypoint.sh"
        validate_configuration
    ) || return 1
    if [ "$OS" = Darwin ] && [ "$BACKEND" = native ]; then
        validate_macos_native_layout || return 1
    fi
    if [ "${SKIP_ENTWARE:-0}" != 1 ]; then
        local filename
        filename=$(installer_filename "$ARCH" "$INSTALLER_LANGUAGE") || return 1
        if [ -n "$installer_dir" ]; then
            INSTALLER_SOURCE=$(cd "$installer_dir" && pwd) || return 1
            [ -s "$INSTALLER_SOURCE/$filename" ] && tar -tzf "$INSTALLER_SOURCE/$filename" >/dev/null || {
                echo "ERROR: Valid installer not found: $installer_dir/$filename" >&2; return 1;
            }
        else
            INSTALLER_TMP=$(mktemp -d "$SCRIPT_DIR/.keenetic-installers-XXXXXX")
            download_installer "$ARCH" "$INSTALLER_LANGUAGE" "$INSTALLER_TMP" || return 1
            chmod 755 "$INSTALLER_TMP"
            chmod 644 "$INSTALLER_TMP/$filename"
            INSTALLER_SOURCE="$INSTALLER_TMP"
        fi
    fi
    local rc=0
    confirm_target || rc=$?
    [ "$rc" = 2 ] && return 0
    [ "$rc" = 0 ] || return "$rc"
    if [ "$BACKEND" = native ] && [ "$OS" = Darwin ]; then
        prepare_usb_macos
        return $?
    fi
    if [ "$BACKEND" = native ]; then
        NATIVE_MOUNT=$(mktemp -d)
        TARGET="$DISK" MOUNT_POINT="$NATIVE_MOUNT" SWAP_SCRIPT="$SCRIPT_DIR/scripts/S01swap" \
            INSTALLER_DIR="$INSTALLER_SOURCE" FORCE=1 bash "$SCRIPT_DIR/entrypoint.sh"
        return $?
    fi

# ============================================================================
# Get Docker image: pull pre-built or build locally
# ============================================================================

# A local helper image wins. Otherwise pull the published image or build it.
# The current entrypoint, platform library and swap script are bind-mounted.
if docker image inspect "$LOCAL_IMAGE" >/dev/null 2>&1; then
    IMAGE="$LOCAL_IMAGE"
else
    echo ">>> Pulling latest pre-built image..."
    if docker pull --platform linux/amd64 "$REMOTE_IMAGE" 2>/dev/null; then
        IMAGE="$REMOTE_IMAGE"
    elif docker image inspect "$REMOTE_IMAGE" >/dev/null 2>&1; then
        echo ">>> Pull failed — using cached tools with the current local scripts..."
        IMAGE="$REMOTE_IMAGE"
    else
        echo ">>> Pull failed, building locally..."
        docker build --platform linux/amd64 \
            --build-arg BASE_IMAGE=cr.yandex/mirror/ubuntu:22.04 \
            --build-arg APT_MIRROR=http://mirror.yandex.ru \
            -t "$LOCAL_IMAGE" "$SCRIPT_DIR"
        IMAGE="$LOCAL_IMAGE"
    fi
    echo ""
fi

# Run the checked-out source even if the cached image contains older scripts.
DOCKER_ENV=( -e "ARCH=$ARCH" -e "INSTALLER_LANGUAGE=$INSTALLER_LANGUAGE" -e FORCE=1 )
DOCKER_TTY=( -i )
if [ -t 0 ] && [ -t 1 ]; then DOCKER_TTY=( -it ); fi
local name
for name in SWAP_SIZE PARTITION_TABLE SKIP_ENTWARE; do
    if [ -n "${!name:-}" ]; then DOCKER_ENV+=( -e "$name=${!name}" ); fi
done
DOCKER_ENV+=( --entrypoint /bin/bash
    -v "$SCRIPT_DIR/entrypoint.sh:/opt/keenetic/entrypoint.sh:ro"
    -v "$SCRIPT_DIR/lib:/opt/keenetic/lib:ro"
    -v "$SCRIPT_DIR/scripts:/opt/scripts:ro" )
if [ -n "$INSTALLER_SOURCE" ]; then
    DOCKER_ENV+=( -v "$INSTALLER_SOURCE:/opt/entware-installers:ro" )
fi

# ============================================================================
# OS detection & run
# ============================================================================
if [ "$OS" = "Linux" ]; then
    # Linux: pass block device directly
    echo ">>> Linux detected — passing block device directly"
    docker run --rm "${DOCKER_TTY[@]}" --privileged --platform linux/amd64 \
        "${DOCKER_ENV[@]}" \
        -v "$DISK":/dev/target \
        "$IMAGE" /opt/keenetic/entrypoint.sh

elif [ "$OS" = "Darwin" ]; then
    # macOS: disk image workflow
    RAW_DISK="${DISK/disk/rdisk}"
    TMP_IMG=$(mktemp "$SCRIPT_DIR/.keenetic-flash-XXXXXX")

    echo "============================================"
    echo " Keenetic Entware Flash — macOS"
    echo "============================================"
    echo ""
    echo "Device:     $DISK"
    echo "Raw device: $RAW_DISK"
    echo ""

    # Step 1: get disk size and create empty image
    echo ">>> Getting disk size..."
    DISK_SIZE=$(diskutil info -plist "$DISK" | plutil -extract TotalSize raw -)
    echo "    Size: $((DISK_SIZE / 1048576)) MB"
    local swap_size="${SWAP_SIZE:-1024}"
    if [ "$DISK_SIZE" -lt "$(((10#$swap_size + 64) * 1048576))" ]; then
        echo "ERROR: Disk is too small for the requested swap and data partitions." >&2
        return 1
    fi

    # Step 1b: verify the card actually stores data across its claimed size.
    # Counterfeit / dead flash reports a huge size but silently drops writes
    # beyond its real (tiny) capacity, so swap (near the start) works while the
    # ext4 data partition never persists. Catch it here instead of after a flash
    # that looks successful but leaves the router with no data partition.
    if [ "${SKIP_CAPACITY_CHECK:-0}" != "1" ]; then
        echo ">>> Verifying real capacity (writes test sectors across the disk)..."
        diskutil unmountDisk force "$DISK" >/dev/null
        if ! python3 -c "
import os, sys, struct, time
rdev, total = sys.argv[1], int(sys.argv[2])
SECT = 512
# exponential points from 1 MiB up (pin-points a tiny fake's real boundary)
# plus ~12 points spread linearly to the last sector
exp = [(1 << 20) << i for i in range(40)]
pts = exp + [total * i // 12 for i in range(1, 12)] + [total - SECT]
pts = sorted(set(p - (p % SECT) for p in pts if 0 < p < total))
def stamp(off):
    tag = b'KEENCAP' + struct.pack('<Q', off) + b'\xa5'
    return (tag * (SECT // len(tag) + 1))[:SECT]
fd = os.open(rdev, os.O_WRONLY)
for off in pts:
    os.lseek(fd, off, os.SEEK_SET); os.write(fd, stamp(off))
os.fsync(fd); os.close(fd)
time.sleep(1)
fd = os.open(rdev, os.O_RDONLY)
bad = [off for off in pts if os.pread(fd, SECT, off) != stamp(off)]
# scrub the test sectors we just wrote
os.close(fd)
fd = os.open(rdev, os.O_WRONLY)
for off in pts:
    if off not in bad:
        os.lseek(fd, off, os.SEEK_SET); os.write(fd, b'\x00' * SECT)
os.fsync(fd); os.close(fd)
if bad:
    first = min(bad)
    sys.stderr.write(
        '\n    FAKE/DEFECTIVE CARD: writes past %.2f GB are silently dropped.\n'
        '    The card reports %.1f GB but cannot store that much, so the data\n'
        '    partition will never appear on the router. Replace the card.\n'
        '    (override with SKIP_CAPACITY_CHECK=1 if you really know better)\n'
        % (first / 1e9, total / 1e9))
    sys.exit(1)
print('    OK: capacity verified across the full %.1f GB.' % (total / 1e9))
" "$RAW_DISK" "$DISK_SIZE"; then
            echo ">>> Aborting — bad USB device."
            exit 1
        fi
    fi

    echo ">>> Creating empty disk image..."
    python3 -c 'import sys; f = open(sys.argv[1], "wb"); f.truncate(int(sys.argv[2])); f.close()' "$TMP_IMG" "$DISK_SIZE"
    chmod 666 "$TMP_IMG"

    # Step 2: run container
    echo ""
    echo ">>> Running container..."
    docker run --rm "${DOCKER_TTY[@]}" --privileged --platform linux/amd64 \
        "${DOCKER_ENV[@]}" \
        -v "$TMP_IMG":/dev/target \
        "$IMAGE" /opt/keenetic/entrypoint.sh

    # Step 3: write image back to USB
    echo ""
    echo ">>> Unmounting $DISK before writing..."
    diskutil unmountDisk force "$DISK"

    TOTAL_GB=$(awk "BEGIN {printf \"%.1f\", $DISK_SIZE / 1073741824}")

    # By default we skip all-zero blocks, which writes only ~200 MB instead of
    # the whole disk. This is safe ONLY because entrypoint.sh formats the ext4
    # partition with the uninit_bg feature: empty block groups are marked
    # uninitialized, so the kernel/e2fsck never read their inode tables and the
    # stale data left in the skipped regions of a used USB is ignored.
    #
    # Set FULL_WRITE=1 to write every block (slow, ~64 GB) — a safe fallback
    # for the rare router whose kernel does not handle uninit_bg.
    if [ "${FULL_WRITE:-0}" = "1" ]; then
        echo ">>> Writing image to $RAW_DISK (${TOTAL_GB} GB, full write)..."
    else
        echo ">>> Writing image to $RAW_DISK (${TOTAL_GB} GB, skipping empty blocks)..."
    fi

    FULL_WRITE="${FULL_WRITE:-0}" python3 -c "
import os, sys, time, errno, subprocess
BLOCK = 4 * 1024 * 1024
BAR_W = 30
full = os.environ.get('FULL_WRITE') == '1'
src, dst, diskdev = sys.argv[1], sys.argv[2], sys.argv[3]
total = os.path.getsize(src)
zero = b'\x00' * BLOCK

def human(n):
    n = float(n)
    for u in ('B', 'KB', 'MB', 'GB', 'TB'):
        if n < 1024 or u == 'TB':
            return ('%d %s' % (n, u)) if u == 'B' else ('%.1f %s' % (n, u))
        n /= 1024

def fmt_t(s):
    s = int(s)
    if s < 60: return '%ds' % s
    if s < 3600: return '%dm%02ds' % (s // 60, s % 60)
    return '%dh%02dm' % (s // 3600, (s % 3600) // 60)

start = time.monotonic()
last = [0.0]
written = 0
data_total = total

def draw(note='', final=False):
    now = time.monotonic()
    if not final and not note and now - last[0] < 0.12:
        return
    last[0] = now
    pct = written * 100 // data_total if data_total else 100
    fill = pct * BAR_W // 100
    bar = '█' * fill + '░' * (BAR_W - fill)
    el = now - start
    spd = written / el if el > 0 else 0
    eta = (data_total - written) / spd if spd > 0 else 0
    msg = '\r  [%s] %3d%%  %s / %s  %s/s  %s  ETA %s' % (
        bar, pct, human(written), human(data_total), human(spd), fmt_t(el), fmt_t(eta))
    if note:
        msg += '  (%s)' % note
    sys.stdout.write(msg + '   ')
    sys.stdout.flush()
    if final:
        sys.stdout.write('\n')

# macOS DiskArbitration may auto-mount the disk again the moment we write a
# valid partition table, grabbing the device and causing 'Resource busy'
# (EBUSY). Force-unmount and retry, showing it on the bar instead of hanging.
def force_unmount():
    subprocess.run(['diskutil', 'unmountDisk', 'force', diskdev],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def retry_busy(fn, what):
    for attempt in range(120):
        try:
            return fn()
        except OSError as e:
            if e.errno == errno.EBUSY:
                draw(note='device busy, freeing... %d' % (attempt + 1))
                force_unmount()
                time.sleep(0.5)
                continue
            raise
    sys.stdout.write('\n')
    sys.exit('ERROR: %s stayed busy while %s. Close Finder/Disk Utility, quit '
             'other disk software, replug the USB, then run again.' % (dst, what))

infd = os.open(src, os.O_RDONLY)

# The temp image is sparse: only the partition table, swap header, ext4
# metadata and Entware are actually allocated (a few MB) — the rest is holes.
# Find those allocated extents up front with SEEK_DATA/SEEK_HOLE (instant, no
# I/O) and write only them. Holes are guaranteed zero; the ext4 uninit_bg
# feature makes the stale data they leave on a used USB harmless. This writes
# megabytes, not the whole 64 GB, and never reads the holes.
if full:
    extents = [(0, total)]
else:
    extents = []
    scan = 0
    while scan < total:
        try:
            ds = os.lseek(infd, scan, os.SEEK_DATA)
        except OSError as e:
            if e.errno == errno.ENXIO:
                break          # no more data — rest of the image is holes
            raise
        if ds >= total:
            break
        try:
            de = min(os.lseek(infd, ds, os.SEEK_HOLE), total)
        except OSError:
            de = total
        if de > ds:
            extents.append((ds, de))
        scan = de if de > scan else scan + BLOCK
data_total = sum(e - s for s, e in extents) or 1

outfd = retry_busy(lambda: os.open(dst, os.O_WRONLY), 'opening device')
draw()
for ds, de in extents:
    pos = ds
    while pos < de:
        n = min(BLOCK, de - pos)
        chunk = os.pread(infd, n, pos)
        if not chunk:
            break
        p = pos
        retry_busy(lambda: (os.lseek(outfd, p, os.SEEK_SET), os.write(outfd, chunk)),
                   'writing at %d MB' % (p // 1048576))
        written += len(chunk)
        pos += len(chunk)
        draw()
os.fsync(outfd)
os.close(outfd)
os.close(infd)
draw(final=True)
print('    Done: wrote %s of real data; skipped %s of empty space (%s disk).' % (
    human(data_total), human(total - data_total), human(total)))
" "$TMP_IMG" "$RAW_DISK" "$DISK"

    echo ">>> Ejecting $DISK..."
    diskutil eject "$DISK" 2>/dev/null || true

    echo ""
    echo "Done! USB drive is ready. Insert it into your Keenetic router."
else
    echo "ERROR: Unsupported OS: $OS"
    exit 1
fi

}

if [ "${RUN_SH_TESTING:-0}" != 1 ]; then
    main "$@"
fi
