"""png_pixels.py - the pixels of a rectangle of a PNG, with the stdlib only.

Used by gallery_items.py to tell whether two rows show the same region (BL-693).
Reads 8-bit, non-interlaced greyscale, RGB, grey+alpha and RGBA PNGs (what a
browser capture is; a palette PNG is not read: its bytes are indices, not
colours). Anything else, and any damaged file, returns None: the caller cannot
compare it, so it keeps the row rather than guessing.
"""
import struct
import zlib

SIGNATURE = b"\x89PNG\r\n\x1a\n"
CHANNELS = {0: 1, 2: 3, 4: 2, 6: 4}


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else (b if pb <= pc else c)


def crop(data, x, y, w, h):
    """Rows y..y+h of the x..x+w columns, as a list of bytes (one per row),
    or None when the PNG is not a shape this reader handles, is damaged, or
    the rectangle leaves the image."""
    try:
        return _crop(data, x, y, w, h)
    except (zlib.error, struct.error, ValueError, IndexError):
        return None


def _crop(data, x, y, w, h):
    if data[:8] != SIGNATURE:
        return None
    pos, idat, head = 8, [], None
    while pos + 8 <= len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        pos += 12 + n
        if kind == b"IHDR":
            head = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    if head is None:
        return None
    width, height, depth, ctype, _, _, interlace = head
    if depth != 8 or interlace or ctype not in CHANNELS:
        return None
    if x < 0 or y < 0 or w <= 0 or h <= 0 or x + w > width or y + h > height:
        return None
    bpp = CHANNELS[ctype]
    stride = width * bpp
    raw = zlib.decompressobj().decompress(b"".join(idat), (stride + 1) * (y + h))
    if len(raw) < (stride + 1) * (y + h):
        return None
    prev = bytearray(stride)
    out = []
    for row in range(y + h):
        ft = raw[row * (stride + 1)]
        cur = bytearray(raw[row * (stride + 1) + 1:(row + 1) * (stride + 1)])
        if ft == 1:
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i - bpp]) & 255
        elif ft == 2:
            for i in range(stride):
                cur[i] = (cur[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                left = cur[i - bpp] if i >= bpp else 0
                cur[i] = (cur[i] + ((left + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                left = cur[i - bpp] if i >= bpp else 0
                ul = prev[i - bpp] if i >= bpp else 0
                cur[i] = (cur[i] + _paeth(left, prev[i], ul)) & 255
        elif ft != 0:
            return None
        if row >= y:
            out.append(bytes(cur[x * bpp:(x + w) * bpp]))
        prev = cur
    return out
