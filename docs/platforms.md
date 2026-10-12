# Router platforms and official installers

Verified on 2026-10-12. This tool runs on a Linux/macOS computer and prepares a
USB drive for Keenetic or Netcraze. OPKG is the package manager; Entware is the
package repository and installer. The router CPU determines the installer.
The computer CPU and Docker image architecture do not determine it.

## Netcraze

Models are taken from the [official catalogue](https://netcraze.ru/ru/products)
and the manufacturer's OPKG guides, including previous generations. NC codes
are listed explicitly; they are not converted to KN codes automatically.

| Model | Platform | Official reference |
| --- | --- | --- |
| Viva NC-1913 | mipsel | [USB installation guide](https://support.netcraze.ru/viva/nc-1913/ru/20980-installing-the-entware-repository-on-a-usb-drive.html) |
| Giga NC-1012 | aarch64 | [USB installation guide](https://support.netcraze.ru/giga/nc-1012/en/20980-installing-the-entware-repository-on-a-usb-drive.html) |
| Giga NC-1013 | aarch64 | [USB installation guide](https://support.netcraze.ru/giga/nc-1013/ru/20980-installing-the-entware-repository-on-a-usb-drive.html) |
| Ultra NC-1812 | aarch64 | [Platform list](https://support.netcraze.ru/viva/nc-1913/ru/69806-installation-of-the-asterisk-ip-pbx-opkg-package.html) |
| Hopper NC-3811 | aarch64 | [Platform list](https://support.netcraze.ru/viva/nc-1913/ru/69806-installation-of-the-asterisk-ip-pbx-opkg-package.html) |
| Hopper SE NC-3812 | aarch64 | [Installation guide](https://support.netcraze.ru/hopper-se/nc-3812/en/18482-installing-opkg-entware-in-the-router-s-internal-memory.html) |
| Hopper 4G+ NC-2312 | aarch64 | [USB installation guide](https://support.netcraze.ru/hopper-4g-plus/nc-2312/ru/20980-installing-the-entware-repository-on-a-usb-drive.html) |
| Hopper DSL NC-3611 | aarch64 | [USB installation guide](https://support.netcraze.ru/hopper-dsl/nc-3611/ru/20980-installing-the-entware-repository-on-a-usb-drive.html) |
| Hero 5G NC-4110 | aarch64 | [Platform list](https://support.netcraze.ru/viva/nc-1913/ru/69806-installation-of-the-asterisk-ip-pbx-opkg-package.html) |
| Titan SE NC-4210 | aarch64 | [USB installation guide](https://support.netcraze.ru/titan-se/nc-4210/ru/20980-installing-the-entware-repository-on-a-usb-drive.html) |

The [Launcher NC-1221](https://netcraze.ru/ru/netcraze-launcher) and
[Carrier NC-1721](https://netcraze.ru/ru/netcraze-carrier) have USB modem functions,
not storage/OPKG functions, and are rejected. A USB connector alone does not
establish OPKG support. Other catalogue models without a verified OPKG platform
are not automatically assigned an installer. Confirm storage support and the
exact architecture in their manual before using an explicit `--arch`.

## Keenetic

The exact IDs below are verified in the manufacturer's
[platform list](https://support.keenetic.com/hero-5g/kn-4110/en/69806-installation-of-the-asterisk-ip-pbx-opkg-package.html)
and [extended platform list](https://support.netcraze.ru/viva/nc-1913/ru/69806-installation-of-the-asterisk-ip-pbx-opkg-package.html).

| Platform | Exact model IDs |
| --- | --- |
| mipsel | KN-1010, KN-1011, KN-1810, KN-1910, KN-1912, KN-1913, KN-2610, KN-2310, KN-2311, KN-2910, KN-3810 |
| mips | KN-2010, KN-2110, KN-2410, KN-2510, KN-2112, KN-3610 |
| aarch64 | KN-2710, KN-1811, KN-1812, KN-1012, KN-3811, KN-3812, KN-2312, KN-4110 |

Do not group models by marketing name or a numerical range. For example,
KN-1810 is mipsel while KN-1811 is aarch64. Unknown models fail explicitly;
the list is a verified subset, not a claim that every other model is unsupported.

## Official downloads

| Router platform | Entware repository | Russian installer | English installer |
| --- | --- | --- | --- |
| mipsel (little endian) | mipselsf-k3.4 | [mipsel-installer.tar.gz](https://bin.entware.net/mipselsf-k3.4/installer/mipsel-installer.tar.gz) | [EN_mipsel-installer.tar.gz](https://bin.entware.net/mipselsf-k3.4/installer/EN_mipsel-installer.tar.gz) |
| mips (big endian) | mipssf-k3.4 | [mips-installer.tar.gz](https://bin.entware.net/mipssf-k3.4/installer/mips-installer.tar.gz) | [EN_mips-installer.tar.gz](https://bin.entware.net/mipssf-k3.4/installer/EN_mips-installer.tar.gz) |
| aarch64 | aarch64-k3.10 | [aarch64-installer.tar.gz](https://bin.entware.net/aarch64-k3.10/installer/aarch64-installer.tar.gz) | [EN_aarch64-installer.tar.gz](https://bin.entware.net/aarch64-k3.10/installer/EN_aarch64-installer.tar.gz) |

Archive names and URLs were checked in the official installer directories:
[MIPSEL](https://bin.entware.net/mipselsf-k3.4/installer/),
[MIPS](https://bin.entware.net/mipssf-k3.4/installer/),
[AArch64](https://bin.entware.net/aarch64-k3.10/installer/).
The downloader uses HTTPS and checks that the response is a nonempty tar.gz
before publishing the filename. This detects truncated archives and error HTML;
it does not provide a separate publisher signature verification.

The [Entware server](https://bin.entware.net/) also lists ARMv5, ARMv7, x86 and
x64 repositories. These are not Keenetic/Netcraze USB installer archives and
are deliberately not offered as router platforms here.

## Usage without Docker

```bash
# List official downloads and verified models. No root or network required.
./run.sh --list-platforms

# Download only: Linux/macOS, no root, Docker or disk required.
./run.sh --model NC-1013 --download-installer ./installers
./run.sh --model KN-2410 --installer-language en --download-installer ./installers-en

# Native Linux preparation (ALL target data is destroyed after confirmation).
sudo apt install parted e2fsprogs util-linux kpartx curl
sudo ./run.sh --backend native --model NC-1812 /dev/sdX
```

`--backend auto` uses Docker when the CLI and daemon work, otherwise it uses
native Linux tools. Missing tools produce installation instructions before disk
selection. `--backend docker` never silently switches to native mode.
macOS automatic flashing requires Docker Desktop and Python 3; it checks both
before selecting a disk. Download-only mode works without them. Manual macOS
partitioning remains documented in README.ru.md.

The download can be copied to the `install` directory on an existing ext4
partition through SMB/FTP. Enable the Open Package support component and select
that partition in the router's OPKG page. Downloading the archive on a computer
does not install packages on that computer or execute router binaries.
