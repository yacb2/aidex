#!/usr/bin/env bash
# Regenerates docs/assets/demo/aidex-artifact-demo.gif (English, under 30 s).
# Needs: ffmpeg, vhs, python3, node with Playwright (global npm root or $PW_ROOT).
# Usage: docs/assets/demo/make-demo-gif.sh [workdir]
set -euo pipefail
_NPM_ROOT="$(npm root -g)"   # resolve before PATH change so the Playwright-bearing node wins
export PATH="$PATH:/opt/homebrew/bin"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
WORK="${1:-${TMPDIR:-/tmp}/aidex-demo-gif}"
# PW_ROOT = directory whose node_modules holds playwright
export PW_ROOT="${PW_ROOT:-$(dirname "$_NPM_ROOT")}"
rm -rf "$WORK"; mkdir -p "$WORK/video"

# 1. Build the real page from the spec with the kit.
python3 "$REPO/skills/artifact/scripts/spec_build.py" "$HERE/migration-consult.spec.md" -o "$WORK/page.html" --check

# 2. Scene 1: terminal with the prompt typed (vhs).
cat > "$WORK/term.tape" <<TAPE
Output "$WORK/term.mp4"
Set Shell "bash"
Set FontSize 21
Set Width 1200
Set Height 750
Set Padding 40
Set Theme "Dracula"
Set TypingSpeed 40ms
Hide
Type "export PS1='> '" Enter
Type "clear" Enter
Show
Sleep 800ms
Type "/aidex:artifact turn our discussion about the migration into a consultation page"
Sleep 1200ms
Enter
Sleep 1500ms
Type "# built with the kit, checked, opened locally: page.html"
Sleep 1500ms
TAPE
vhs "$WORK/term.tape"

# 3. Scene 2: Playwright video of the real page.
node "$HERE/record-page.mjs" "$WORK/page.html" "$WORK/video"
mv "$WORK"/video/*.webm "$WORK/page.webm"

# 4. Concatenate and convert to a GIF.
ffmpeg -y -loglevel error -i "$WORK/term.mp4" -i "$WORK/page.webm" \
  -filter_complex "[0:v]fps=10,scale=960:-2,setsar=1[a];[1:v]fps=10,scale=960:-2,setsar=1[b];[a][b]concat=n=2:v=1:a=0,split[s0][s1];[s0]palettegen=max_colors=96[p];[s1][p]paletteuse=dither=bayer:bayer_scale=4" \
  "$HERE/aidex-artifact-demo.gif"
ls -l "$HERE/aidex-artifact-demo.gif"
ffprobe -v error -show_entries format=duration -of csv=p=0 "$HERE/aidex-artifact-demo.gif"
