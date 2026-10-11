#!/bin/bash
set -e
# Built from a real scenario's SHAPE (LOOP-012 campaign 2); the content is neutral.
printf '# Project\n\nSmall shop admin: orders, customers, a Django back office.\n' > CLAUDE.md
mkdir -p .context/reports .context/shots
# Suppress the style-profile offer: these cases measure the page, not onboarding.
touch .context/.aidex-artifact-style-offered
python3 - <<'PY'
import struct, zlib
def png(path, rgb, w=320, h=200):
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
png(".context/shots/order-list-today.png", (225, 228, 235))
png(".context/shots/order-list-today-narrow.png", (215, 222, 232), 160, 280)
PY
cat > .context/shots/README.md <<'MDOC'
Real captures of the orders list as it is today:
- order-list-today.png: desktop width, the table with no filters
- order-list-today-narrow.png: phone width, the same table

The filter panel does not exist yet: there is no capture of it.
MDOC
