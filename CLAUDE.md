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

## Agent tooling: MCP servers

`.mcp.json` (Claude Code) and `.codex/config.toml` (Codex) declare the same
two servers. Both agents are expected to run from the repo root; the paths
are relative to it.

- **whiteboard** — a canvas for diagrams (boxes, arrows, flowcharts, PNG/SVG
  export). Runs via `npx`, nothing to build. It is licensed: export
  `WHITEBOARD_MCP_LICENSE_KEY` in the shell that starts the agent. Claude's
  config forwards it; for Codex put it under `[mcp_servers.whiteboard.env]`
  in your personal `~/.codex/config.toml`, never in the repo.
- **scenic-mcp** — drives the running app: screenshots, viewport inspection,
  clicks and keystrokes. `tools/mcp/scenic_mcp.sh` launches the Node server
  from the sibling `../scenic_mcp_experimental` checkout, which must be built
  once per machine (`npm install && npm run build` there). The app must be
  running (`iex -S mix`, port 9997) before the server has anything to talk to.
