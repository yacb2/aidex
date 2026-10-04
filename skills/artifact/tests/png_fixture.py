#!/usr/bin/env python3
"""png_fixture.py <out.png> <width> <height> [grey 0-255] — write a real, flat-grey PNG
(default 128; a second level makes a capture whose bytes differ).

The gallery tests need captures the generator can open (it reads each tile's
size from the PNG header and refuses a missing file) without committing
binaries or depending on a project's screenshot tree.
"""
import struct
import sys
import zlib


def chunk(kind, data):
    return (struct.pack(">I", len(data)) + kind + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff))


path, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
grey = int(sys.argv[4]) if len(sys.argv) > 4 else 128
raw = b"".join(b"\x00" + bytes([grey]) * 3 * w for _ in range(h))
with open(path, "wb") as fh:
    fh.write(b"\x89PNG\r\n\x1a\n"
             + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
             + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
