import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("macos_disk", Path(__file__).resolve().parents[1] / "lib/macos_disk.py")
disk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(disk)


class NativeDiskTests(unittest.TestCase):
    def test_swap_one_gib_matches_linux_v1_layout(self):
        for arch, version_bytes in (("mipsel", b"\x01\x00\x00\x00"), ("aarch64", b"\x01\x00\x00\x00"), ("mips", b"\x00\x00\x00\x01")):
            with self.subTest(arch=arch):
                header = disk.swap_header(1073741824, arch)
                self.assertEqual(len(header), 4096)
                self.assertEqual(header[:1024], bytes(1024))
                self.assertEqual(header[1024:1028], version_bytes)
                self.assertEqual(int.from_bytes(header[1028:1032], "big" if arch == "mips" else "little"), 262143)
                self.assertEqual(header[1032:1036], bytes(4))
                self.assertEqual(header[1052:1068], b"SWAP" + bytes(12))
                self.assertEqual(header[4086:], b"SWAPSPACE2")

    def test_swap_uses_router_page_size_and_preserves_remaining_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "swap.bin"
            path.write_bytes(b"\xff" * 32768)
            disk.initialize_swap(str(path), 1073741824, "aarch64", 16384)
            content = path.read_bytes()
            self.assertEqual(content[16374:16384], b"SWAPSPACE2")
            self.assertEqual(content[16384:], b"\xff" * 16384)

    def test_mbr_changes_only_linux_partition_types(self):
        original = bytearray(512)
        original[510:] = b"\x55\xaa"
        original[450] = original[466] = 0x0C
        struct.pack_into("<II", original, 454, 2048, 2097152)
        struct.pack_into("<II", original, 470, 2101248, 200000)
        result = disk.linux_mbr(original, 1073741824, 2 * 1073741824)
        expected = bytearray(original)
        expected[450], expected[466] = 0x82, 0x83
        self.assertEqual(result, expected)
        with self.assertRaises(ValueError):
            disk.linux_mbr(original, 1073741824 - 512, 2 * 1073741824)
        with self.assertRaises(ValueError):
            disk.linux_mbr(original, 1073741824, 1073741824)

    def test_invalid_header_configuration_rejected(self):
        for size, arch, page in ((0, "mipsel", 4096), (1073741824, "x86_64", 4096), (1073741824, "aarch64", 512)):
            with self.assertRaises(ValueError):
                disk.swap_header(size, arch, page)


if __name__ == "__main__":
    unittest.main()
