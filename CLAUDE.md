# Quillex / Franklin — Claude Notes

## Running spex tests

Always use `scripts/run_spex.sh`. It boots `tools/window_pinner` so spex
windows stay pinned to the current desktop. Running `mix spex` directly
scatters windows across desktops and is not supported for interactive
development.

Prefer the quiet wrapper — full output goes to a /tmp log file and only the
failure list + summary reach the terminal (essential for agent workflows,
pleasant for humans):

  scripts/run_spex_quiet.sh                              # all spex
  scripts/run_spex_quiet.sh test/spex/quillex/20_*.exs   # one file

`scripts/run_spex.sh` is the same thing with full output streaming.
