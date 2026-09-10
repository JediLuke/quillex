#!/usr/bin/env bash
# Record and assemble the README gif.
#
#   scripts/make_readme_gif.sh              # -> assets/demo.gif
#   scripts/make_readme_gif.sh out.gif      # -> somewhere else
#
# Runs test/spex/quillex/61_readme_gif_spex.exs (which only runs with
# QUILLEX_GIF=1) against a clean XDG config so a saved theme cannot leak into
# the recording, then assembles the frames with scripts/assemble_gif.py via uv.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-assets/demo.gif}"
FRAMES="$(mktemp -d /tmp/quillex_gif_frames.XXXXXX)"
XDG="$(mktemp -d /tmp/quillex_gif_xdg.XXXXXX)"

echo "recording frames into $FRAMES"
QUILLEX_GIF=1 QUILLEX_GIF_FRAMES="$FRAMES" XDG_CONFIG_HOME="$XDG" \
  bash scripts/run_spex_quiet.sh test/spex/quillex/61_readme_gif_spex.exs

echo "assembling $OUT"
uv run scripts/assemble_gif.py "$FRAMES" "$OUT" ${GIF_WIDTH:+--width "$GIF_WIDTH"}
rm -rf "$XDG"
echo "frames kept in $FRAMES (delete when happy)"
