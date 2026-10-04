#!/usr/bin/env python3
"""png_fixture.py <out.png> <width> <height> [grey 0-255 [x,y,w,h,level [rgba]]] — write a
real, flat-grey PNG (default 128; a second level makes a capture whose bytes
differ). The optional block paints the rectangle x,y,w,h at `level`; `rgba`
writes a colour-type-6 file instead of RGB.

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
block = [int(v) for v in sys.argv[5].split(",")] if len(sys.argv) > 5 else None
rgba = len(sys.argv) > 6 and sys.argv[6] == "rgba"
ch = 4 if rgba else 3


def pixel(cx, cy):
    g = grey
    if block and block[0] <= cx < block[0] + block[2] and block[1] <= cy < block[1] + block[3]:
        g = block[4]
    return bytes([g]) * 3 + (b"\xff" if rgba else b"")


raw = b"".join(b"\x00" + b"".join(pixel(cx, cy) for cx in range(w)) for cy in range(h))
with open(path, "wb") as fh:
    fh.write(b"\x89PNG\r\n\x1a\n"
             + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6 if rgba else 2, 0, 0, 0))
             + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
