# Keenetic / Netcraze Entware Flash

**Prepare a USB flash drive for Entware on Keenetic routers — with a single command.**

[Русский](README.ru.md) | [中文](README.zh.md)

## Quick Start

Insert a USB flash drive and run:

```bash
git clone https://github.com/onepyad/keenetic-entware-flash.git
cd keenetic-entware-flash
# macOS: install/check Homebrew, Python and e2fsprogs first
if [ "$(uname -s)" = Darwin ]; then bash setup-macos.sh; fi
sudo bash run.sh
```

Disconnect all other external drives when prompted. The only remaining USB drive is selected automatically:

```
Отключите все остальные флешки и внешние диски.
Оставьте подключённой только флешку, которую хотите подготовить.
Когда готово, нажмите Enter (или введите 0 для отмены):
  Media Name: USB DISK 2.0
  Disk Size: 16.0 GB (...)
Автоматически выбрана флешка: /dev/disk4
```

Docker is checked before disk selection. Linux can flash using native tools; Docker mode pulls an image or builds it locally.

## Requirements

What you need depends on which script you run:

| Script | macOS | Linux |
|--------|-------|-------|
| `run.sh` (flash a drive) | Homebrew + Python + e2fsprogs **or** Docker Desktop + Python | Docker **or** `parted`, `e2fsprogs`, `util-linux`, `kpartx` |
| `clone.sh backup` | built-in (`dd`, `diskutil`) | built-in (`dd`, `lsblk`) |
| `clone.sh restore` (with auto-expand) | Docker Desktop | `parted`, `e2fsprogs`, `util-linux`, `kpartx`, `gdisk` |
| `clone.sh restore --no-expand` | built-in | built-in |
| `check.sh` (quick / full / write) | built-in | built-in |
| `check.sh entware` (deep verify) | `e2fsprogs` (+ Docker not needed) | `e2fsprogs` |

### macOS

```bash
# Docker Desktop — needed for run.sh and for clone.sh restore with ext4 expansion.
# macOS cannot resize ext4 natively, so a Linux helper container does it.
brew install --cask docker
# then launch Docker Desktop once so the daemon is running

# e2fsprogs — needed for check.sh entware and ext4 integrity checks.
# Provides e2fsck and debugfs. Homebrew installs it keg-only (not on PATH);
# check.sh finds it automatically in the keg.
brew install e2fsprogs

# ddrescue — only needed to rescue a failing/dying drive (see "Recovering a dying drive").
brew install ddrescue
```

> Docker Desktop file sharing must allow `/Users` (the default). `clone.sh`
> places its temporary images under `~/.cache/keenetic-flash` so the helper
> container can mount them.

### Linux

```bash
# Debian / Ubuntu (and most router hosts)
sudo apt install docker.io parted e2fsprogs util-linux kpartx gdisk gddrescue

# Docker is optional on Linux: run.sh and clone.sh can use native system tools.
```

## Supported Models

Use the exact **KN-xxxx** (Keenetic) or **NC-xxxx** (Netcraze) model ID.
The host CPU does not determine the router platform. See
[verified models, official sources and download links](docs/platforms.md).

| Platform | Keenetic examples | Verified Netcraze models |
| --- | --- | --- |
| `mipsel` | KN-1810, KN-3810, KN-1010/1011 | Viva NC-1913 |
| `mips` | KN-2410, KN-2510, KN-2010, KN-2110, KN-3610 | No verified NC models in this list |
| `aarch64` | KN-2710, KN-1811/1812, KN-1012, KN-3811/3812 | Giga NC-1012/1013, Ultra NC-1812, Hopper NC-3811, Hopper SE NC-3812, Hopper 4G+ NC-2312, Hopper DSL NC-3611, Hero 5G NC-4110, Titan SE NC-4210 |

Launcher NC-1221 and Carrier NC-1721 support USB modems rather than USB
storage/OPKG. Unknown IDs require you to verify their manual and specify `--arch`.

```bash
./run.sh --list-platforms
sudo ./run.sh --model NC-1812 /dev/sdX
# Download only: no root, Docker or disk access
./run.sh --model NC-1013 --download-installer ./installers
./run.sh --model KN-2410 --installer-language en --download-installer ./installers-en
```

### Without Docker

Linux automatically falls back to native tools when Docker CLI or its daemon
is unavailable. Select `--backend native` explicitly if preferred:

```bash
sudo apt install parted e2fsprogs util-linux kpartx curl
sudo ./run.sh --backend native --model NC-1913 /dev/sdX
```

macOS supports native preparation: `bash setup-macos.sh`, then
`sudo bash run.sh --backend native`. Dependencies are checked before disk selection. `--backend docker` never switches backends.

The selected archive is downloaded over HTTPS from `bin.entware.net` and checked
before formatting. Network errors or invalid archives stop preparation.
On macOS, confirmation precedes the destructive capacity test as well as flashing.

## Parameters

| Variable | Description | Default |
|---|---|---|
| `MODEL` | KN-xxxx / NC-xxxx | — |
| `BACKEND` | auto / docker / native (Linux/macOS) | `auto` |
| `INSTALLER_LANGUAGE` | ru / en | `ru` |
| `ARCH` | Router architecture: `mipsel`, `mips`, `aarch64` | Model/platform selection |
| `SWAP_SIZE` | Swap partition size in MB | `1024` |
| `PARTITION_TABLE` | Partition table: `mbr` or `gpt` | `mbr` |
| `SKIP_ENTWARE` | Skip Entware installer (`1` to skip) | `0` |

## Examples

```bash
# Interactive — pick your USB from a list
sudo ./run.sh

# Specify device directly
sudo ./run.sh /dev/disk4          # macOS
sudo ./run.sh /dev/sdb            # Linux

# AArch64 (Peak, Titan, Hopper) with GPT and 512MB swap
sudo ARCH=aarch64 SWAP_SIZE=512 PARTITION_TABLE=gpt ./run.sh

# Partition only, no Entware
sudo SKIP_ENTWARE=1 ./run.sh
```

## Direct Docker Usage (Linux)

```bash
docker run --rm -it --privileged \
  -v /dev/sdb:/dev/target \
  ghcr.io/onepyad/keenetic-entware-flash:main
```

## Native macOS preparation without Docker

```bash
bash setup-macos.sh
sudo bash run.sh --backend native
# Reuse an archive you have already downloaded:
sudo bash run.sh --backend native --installer-dir ./installers
```

Homebrew is not bundled with macOS. The setup script checks it, uses the official
installer if missing, and installs Git, Python and e2fsprogs. Run setup without sudo.
Before detection, disconnect all other USB drives and external disks. Exactly one
candidate is selected and described; zero or multiple candidates require a rescan.
The script still requires confirmation before erasing the drive.

Native mode creates MBR with an initialized **1 GiB Linux swap** partition and
an **OPKG ext4** partition using the remaining space, with the installer and swap
startup script copied from the Mac. No additional SMB copy is needed.
This mode supports 512-byte disk sectors and disks up to 2 TiB. `SWAP_SIZE` is in
MiB (default 1024), and `SWAP_PAGE_SIZE` is the router's Linux page size (default
4096, independent of the Mac CPU). See [macOS testing instructions](TESTING.ru.md).

Read-only USB detection without Docker or root:

```bash
DISK="$(bash run.sh --detect-usb)"
```

## How It Works

1. `run.sh` lists USB devices and prompts you to select one
2. Pulls the pre-built Docker image (or builds locally if unavailable)
3. On macOS — creates a temporary disk image; on Linux — passes the device directly
4. The container creates an MBR/GPT partition table:
   - **Partition 1** — SWAP
   - **Partition 2** — EXT4 (label: OPKG) with Entware installer
5. On macOS — writes the image to USB (skipping empty blocks for speed)
6. Done — insert the drive into your router

## After Flashing

### Step 1: Install OPKG

1. Insert the USB drive into the Keenetic router
2. Open the router web UI (usually http://192.168.1.1)
3. Go to **Management** → **General Settings** → **Updates and Component Options**
4. Find and install **OPKG Package Manager**:
   > Allows installing OpenWRT packages to extend the router's functionality.
   > Community support is available at [forum.keenetic.ru](https://forum.keenetic.ru). Keenetic technical support does not cover these topics.
5. The router will reboot and start installing Entware automatically

You can monitor the installation progress in the router log:
**Diagnostics** → **General** → **Log** (`/diagnostics/general/log`)

When finished, you will see:
```
[5/5] Installation of "Entware" package system is complete!
Don't forget to change the password and port number!
```

### Step 2: Change Password and Configure SSH

After installation, Entware provides its own SSH access (Dropbear):
- **Login:** `root`
- **Password:** `keenetic`
- **Port:** `222`

Connect and change the default password immediately:

```bash
ssh root@192.168.1.1 -p 222

passwd root
# Changing password for root
# New password:
# Retype password:
# passwd: password for root changed by root
```

Update the package list and installed packages:

```bash
opkg update
opkg upgrade
```

#### Configure SSH Ports

After installing Entware, you will have two SSH services. It's recommended to move the built-in Keenetic SSH to a different port to avoid conflicts:

**Option A: Via web UI**
1. Open router web UI → **Management** → **General Settings**
2. Find **Command Line** or **Remote Access** section
3. Change SSH port from `22` to `2222`

**Option B: Via Keenetic CLI**
```bash
ssh admin@192.168.1.1 -p 22

(config)> ip ssh
(config-ssh)> port 2222
(config-ssh)> exit
(config)> system configuration save
```

After configuration, you will have two separate SSH connections:

```bash
# Keenetic CLI (router management)
ssh admin@192.168.1.1 -p 2222

# Entware shell (full Linux environment)
ssh root@192.168.1.1 -p 22
```

> Entware SSH port can be changed in `/opt/etc/config/dropbear.conf` if needed.

### Step 3: Enable SWAP (Recommended)

Swap significantly improves stability when running multiple Entware packages. SWAP **does not activate automatically** without an init script — after each router reboot `free -m` will show `Swap: 0`.

The auto-start script is already saved to the USB drive during flashing. It identifies a Linux swap partition labeled SWAP and runs `swapon`. It never formats a device; repeated start is safe.

Connect to Entware via SSH and run:

Copy the script to auto-start:

```bash
cp /opt/scripts/S01swap /opt/etc/init.d/S01swap && chmod +x /opt/etc/init.d/S01swap
```

Run it — the script will find the partition, initialize and activate SWAP:

```bash
/opt/etc/init.d/S01swap start
```

Verify:

```bash
/opt/etc/init.d/S01swap status
```

```bash
free -m
```

The `Swap` line should show values (e.g., `Swap: 1023 MB`).

---



---

After rebooting the router, SWAP will activate automatically. Verify:

```bash
free -m
```

```bash
cat /proc/swaps
```

### Step 4: Verify

```bash
# Check Entware is working
opkg update
opkg list-installed

# Check swap is active
free -m
```

More info: [help.keenetic.com](https://help.keenetic.com/hc/en/articles/360021888880)

## Local Build

```bash
# Standard build
docker build --platform linux/amd64 -t keenetic-entware-flash .

# Build in Russia (with accessible mirrors)
docker build --platform linux/amd64 \
  --build-arg BASE_IMAGE=cr.yandex/mirror/ubuntu:22.04 \
  --build-arg APT_MIRROR=http://mirror.yandex.ru \
  -t keenetic-entware-flash .
```

## USB Clone (Backup / Restore)

USB drives in routers run 24/7 and can wear out. Use `clone.sh` to create a full byte-for-byte backup of your USB drive and restore it to a new one.

### Backup (USB → file)

```bash
# Interactive USB selection
sudo ./clone.sh backup

# Specify device directly
sudo ./clone.sh backup /dev/disk4          # macOS
sudo ./clone.sh backup /dev/sdb            # Linux

# Custom output path
sudo ./clone.sh backup /dev/disk4 ~/backup.img

# Compressed backup (gzip)
sudo ./clone.sh backup --compress
sudo ./clone.sh backup /dev/disk4 --compress
```

Default output: `~/keenetic-backup-YYYY-MM-DD.img`

### Restore (file → USB)

```bash
# Interactive USB selection
sudo ./clone.sh restore backup.img

# Specify device directly
sudo ./clone.sh restore backup.img /dev/disk4

# Restore exact original layout without expanding partition 2
sudo ./clone.sh restore backup.img /dev/disk4 --no-expand
```

- Compressed images (`.img.gz`) are detected automatically
- Backup and restore progress is shown inline with done, total, remaining size, and speed
- Raw images are written exactly, including zero-filled blocks
- When the target drive is larger than the image, partition 2 (ext4 / OPKG) is expanded automatically
- On macOS, automatic ext4 expansion uses Docker because macOS cannot resize ext4 filesystems natively
- The script checks that the image fits on the target disk
- Confirmation is required before writing

## USB Health Check

USB drives in routers run 24/7 and eventually fail. `check.sh` diagnoses a drive's
health and verifies a cloned Entware layout, so you can tell a dying drive from a
good one before trusting it with data.

```bash
# List all disks (no sudo needed) — find your device node
./check.sh list

# Quick check: info, read probes (start/middle/end), speed, read-only fsck
sudo ./check.sh quick /dev/disk4        # macOS
sudo ./check.sh quick /dev/sdb          # Linux

# Full read scan of the whole device (slow, catches bad blocks anywhere)
sudo ./check.sh full /dev/disk4

# Verify a cloned Entware drive: partitions, ext4 fsck, swap, Entware markers
sudo ./check.sh entware /dev/disk4

# Destructive write/verify test — WIPES ALL DATA, only for confirming a suspect drive
sudo ./check.sh write /dev/disk4
```

### Modes

| Mode | What it does |
|------|--------------|
| `list` | Lists every disk (internal + USB). No sudo required. |
| `quick` (default) | Device info, read probes at start/middle/end, sequential read speed, read-only filesystem check. Samples ~12 MiB. |
| `full` | Everything in `quick` plus a full sequential read of the entire device with live progress (percent, avg/instant speed, ETA). Reveals bad blocks anywhere on the drive. |
| `entware` | Verifies a restored Keenetic Entware drive: partition layout, ext4 magic, `e2fsck` integrity, swap partition (recognized by the `SWAP` volume label), and Entware markers (`/opt`, `/bin/opkg`, `/etc/opkg.conf`, `/etc/init.d`). |
| `write` | **Destructive.** Overwrites the first 256 MiB with a random pattern and verifies the read-back. Requires typing `YES`. Use only to confirm a drive is dying. |

### Deep verification (recommended for `entware` and `quick`)

The `entware` and filesystem-check stages need the `e2fsprogs` tools (`e2fsck`,
`debugfs`). On macOS they are not bundled and Homebrew installs them keg-only —
`check.sh` resolves them automatically from the Homebrew keg, but you must install
them first:

```bash
brew install e2fsprogs            # macOS
sudo apt install e2fsprogs        # Debian / Ubuntu / Linux router host
```

Without `e2fsprogs`, `check.sh` still detects partition types via on-disk magic
signatures, but cannot run integrity checks or list filesystem contents.

### Recovering a dying drive

If `full` or a backup aborts with `Input/output error` or
`OSError: [Errno 6] Device not configured`, the drive's controller is failing —
plain `dd` stops at the first bad sector. Use `ddrescue`, which skips errors,
retries, and keeps a map so you can resume after replugging:

```bash
brew install ddrescue                                            # macOS
sudo ddrescue -d -r0 -b 4096 /dev/rdisk4 rescue.img rescue.map   # fast first pass
sudo ddrescue -d -r3 -R      /dev/rdisk4 rescue.img rescue.map   # retry bad zones
```

Then repair and restore the rescued image:

```bash
brew install e2fsprogs
sudo ./clone.sh restore rescue.img /dev/diskN
sudo ./check.sh entware /dev/diskN
```

## Troubleshooting

**"No external USB devices found"** — insert a USB flash drive and try again.

**"Permission denied"** — run with `sudo`:
```bash
sudo ./run.sh
```

**macOS: "Resource busy"** — the script unmounts automatically, but if it fails:
```bash
diskutil unmountDisk /dev/diskN
```

**Docker Hub / GHCR unavailable** — the script will automatically build the image locally using accessible mirrors.

**Entware installer failed to download** — preparation stops before formatting. Check access to `bin.entware.net` and retry. `SKIP_ENTWARE=1` explicitly allows preparation without an installer.

## License

MIT — see [LICENSE](LICENSE).
