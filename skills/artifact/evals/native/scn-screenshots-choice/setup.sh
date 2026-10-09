#!/bin/bash
set -e
# Built from a real scenario's SHAPE (LOOP-012); the content is neutral.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="$REPO/skills/artifact/scripts"
printf '# Project\n\nSmall shop admin: orders, customers, a Django back office.\n' > CLAUDE.md
mkdir -p .context/research .context/reports
# Suppress the style-profile offer: these cases measure the page, not onboarding.
touch .context/.aidex-artifact-style-offered

mkdir -p .context/shots
python3 - <<'PY'
import struct, zlib
def png(path, rgb, w=320, h=200):
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
for name, rgb in (("a", (210, 90, 90)), ("b", (90, 170, 110)), ("c", (90, 110, 200))):
    png(f".context/shots/order-screen-{name}.png", rgb)
PY
cat > .context/shots/README.md <<'MDOC'
Three candidate layouts of the order detail screen:
- a: one column, actions at the bottom
- b: two columns, actions in a side panel
- c: tabs (summary, items, history), actions in the header
MDOC
