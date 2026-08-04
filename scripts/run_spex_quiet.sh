#!/usr/bin/env bash
# Run spex via run_spex.sh with full output captured to a log file,
# printing only a compact summary (failure headers + result counts).
# Intended for agent-driven runs: keeps multi-thousand-line suite output
# out of the conversation; inspect the log file for details.
#
# Usage: scripts/run_spex_quiet.sh [spex files...]
#   SPEX_LOG=/path/to.log scripts/run_spex_quiet.sh   # optional log override

set -u
export PATH="$HOME/.asdf/shims:$HOME/.asdf/bin:$PATH"

LOG="${SPEX_LOG:-/tmp/spex_run_$(date +%Y%m%d_%H%M%S).log}"
JSONL="${SPEX_JSONL:-${LOG%.log}.failures.jsonl}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rm -f "$JSONL"
SPEX_JSONL="$JSONL" "$SCRIPT_DIR/run_spex.sh" "$@" > "$LOG" 2>&1
EXIT=$?

echo "exit: $EXIT"
echo "log:  $LOG"
echo "jsonl: $JSONL"
echo "--- failures ---"
grep -nE "^\s+[0-9]+\) " "$LOG" | head -40
echo "--- summary ---"
grep -E "[0-9]+ (doctest|test|spex|scenario)s?,.*[0-9]+ failure" "$LOG" | tail -5
grep -E "Finished in" "$LOG" | tail -2

exit $EXIT
