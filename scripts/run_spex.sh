#!/usr/bin/env bash
# Run spex with the window pinner active so test windows stay on the
# current desktop. Ctrl+C stops both the pinner and the spex run.
#
# NOTE: window_pinner captures the desktop at startup. Run this script
# from a shell on the desktop you want spex windows to land on.
#
# Usage: scripts/run_spex.sh [spex-file-or-dir]
set -euo pipefail
cd "$(dirname "$0")/.."

# The pinner is an X11/EWMH daemon, so it only exists where X11 does. It is a
# convenience — it keeps test windows on the current desktop — not a
# requirement, so off X11 (macOS without XQuartz) skip it and run spex
# directly. Mix.Tasks.RunSpex guards the same way before starting it.
PINNER_BIN="./tools/window_pinner"
if [ -n "${DISPLAY:-}" ]; then
  if [ ! -x "$PINNER_BIN" ]; then
    echo "Building window_pinner..."
    (cd tools && make)
  fi

  "$PINNER_BIN" &
  PINNER_PID=$!
  trap 'kill "$PINNER_PID" 2>/dev/null || true' EXIT
else
  echo "No DISPLAY — skipping window_pinner (spex windows will land wherever the WM puts them)."
fi

# If the forks are checked out beside us but QUILLEX_LOCAL_DEPS is not set,
# say so. mix.exs defaults to pinned GitHub revisions, so the suite would run
# against those and quietly ignore local edits to scenic or the widget library
# — you would be testing something other than what you are looking at.
if [ "${QUILLEX_LOCAL_DEPS:-}" != 1 ] && [ "${QUILLEX_LOCAL_DEPS:-}" != true ] &&
  [ -d ../scenic-widget-contrib ] && [ -d ../scenic ]; then
  echo "note: sibling forks are checked out, but QUILLEX_LOCAL_DEPS is not set —"
  echo "      running against the PINNED revisions in mix.exs, not your local edits."
  echo "      Export QUILLEX_LOCAL_DEPS=1 to test the checkouts beside this one."
  echo
fi

JSONL="${SPEX_JSONL:-/tmp/quillex_spex_failures_$(date +%Y%m%d_%H%M%S).jsonl}"
MIX_ENV=test SCENIC_LOCAL_TARGET=glfw mix spex --jsonl="$JSONL" "$@"
