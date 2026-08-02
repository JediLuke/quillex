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

PINNER_BIN="./tools/window_pinner"
if [ ! -x "$PINNER_BIN" ]; then
  echo "Building window_pinner..."
  (cd tools && make)
fi

"$PINNER_BIN" &
PINNER_PID=$!
trap 'kill "$PINNER_PID" 2>/dev/null || true' EXIT

JSONL="${SPEX_JSONL:-/tmp/quillex_spex_failures_$(date +%Y%m%d_%H%M%S).jsonl}"
MIX_ENV=test SCENIC_LOCAL_TARGET=glfw mix spex --jsonl="$JSONL" "$@"
