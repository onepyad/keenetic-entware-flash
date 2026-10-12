"""Linux swap v1 and MBR types for native macOS preparation.

Swap layout: util-linux/include/swapheader.h and disk-utils/mkswap.c.
No router binaries or host CPU-dependent page sizes are used.
"""
import argparse
import os
import struct
import uuid


def swap_header(size, arch, page_size=4096):
    if arch not in ("mipsel", "mips", "aarch64"):
        raise ValueError("unsupported router architecture")
    if page_size not in (4096, 8192, 16384, 65536):
        raise ValueError("unsupported router swap page size")
    pages = size // page_size
    if pages < 10 or pages > 0xFFFFFFFF:
        raise ValueError("invalid swap capacity")
    header = bytearray(page_size)
    # bootbits[1024], version, last_page, nr_badpages, uuid[16], label[16].
    endian = ">" if arch == "mips" else "<"
    struct.pack_into(endian + "III", header, 1024, 1, pages - 1, 0)
    header[1036:1052] = uuid.uuid4().bytes
    header[1052:1056] = b"SWAP"
    header[-10:] = b"SWAPSPACE2"
    return bytes(header)


def write_at(fd, offset, data):
    os.lseek(fd, offset, os.SEEK_SET)
    remaining = memoryview(data)
    while remaining:
        written = os.write(fd, remaining)
        if written <= 0:
            raise OSError("short device write")
        remaining = remaining[written:]


def initialize_swap(path, size, arch, page_size=4096):
    header = swap_header(size, arch, page_size)
    fd = os.open(path, os.O_RDWR)  # Never create a missing device/file.
    try:
        write_at(fd, 0, header)
        os.fsync(fd)
        os.lseek(fd, 0, os.SEEK_SET)
        if os.read(fd, len(header)) != header:
            raise OSError("swap header verification failed")
    finally:
        os.close(fd)


def linux_mbr(sector, swap_size, disk_size):
    if len(sector) != 512 or sector[510:] != b"\x55\xaa":
        raise ValueError("invalid MBR signature or sector size")
    entries = []
    for index in range(4):
        offset = 446 + 16 * index
        kind = sector[offset + 4]
        start, count = struct.unpack_from("<II", sector, offset + 8)
        entries.append((kind, start, count))
    first, second = entries[:2]
    if first[0] not in (0x0B, 0x0C, 0x82) or second[0] not in (0x0B, 0x0C, 0x83):
        raise ValueError("unexpected partition types")
    if any(kind or start or count for kind, start, count in entries[2:]):
        raise ValueError("expected exactly two partitions")
    if first[2] * 512 != swap_size:
        raise ValueError("swap partition is not the requested exact size")
    if first[1] < 1 or first[1] + first[2] > second[1] or second[2] < 131072:
        raise ValueError("invalid or overlapping partition boundaries")
    if (second[1] + second[2]) * 512 > disk_size:
        raise ValueError("partition exceeds disk capacity")
    result = bytearray(sector)
    result[450] = 0x82  # Linux swap
    result[466] = 0x83  # Linux filesystem
    return bytes(result)


def patch_mbr(path, swap_size, disk_size):
    fd = os.open(path, os.O_RDWR)
    try:
        sector = os.read(fd, 512)
        updated = linux_mbr(sector, swap_size, disk_size)
        write_at(fd, 0, updated)
        os.fsync(fd)
        os.lseek(fd, 0, os.SEEK_SET)
        if os.read(fd, 512) != updated:
            raise OSError("MBR verification failed")
    finally:
        os.close(fd)


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="operation", required=True)
    swap = sub.add_parser("swap")
    swap.add_argument("path")
    swap.add_argument("size", type=int)
    swap.add_argument("arch", choices=("mipsel", "mips", "aarch64"))
    swap.add_argument("page_size", type=int)
    mbr = sub.add_parser("mbr")
    mbr.add_argument("path")
    mbr.add_argument("swap_size", type=int)
    mbr.add_argument("disk_size", type=int)
    args = parser.parse_args()
    if args.operation == "swap":
        initialize_swap(args.path, args.size, args.arch, args.page_size)
        print("Linux SWAP v1 initialized and verified")
    else:
        patch_mbr(args.path, args.swap_size, args.disk_size)
        print("MBR types verified: partition 1 = Linux swap, partition 2 = Linux ext4")


if __name__ == "__main__":
    main()
