# Quillex / Franklin — Claude Notes

## Running spex tests

Always use `scripts/run_spex.sh`. It boots `tools/window_pinner` so spex
windows stay pinned to the current desktop. Running `mix spex` directly
scatters windows across desktops and is not supported for interactive
development.

Usage:
  scripts/run_spex.sh                              # all spex
  scripts/run_spex.sh test/spex/quillex/20_*.exs   # one file
