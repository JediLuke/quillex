# Cycle decision: `.mcp.json` staging

**Date:** 2026-05-02
**Cycle task:** "Decide on .mcp.json staging — local-machine config vs. cross-developer change"

## Decision

**EXCLUDE** — do not stage `.mcp.json` in Task 4's commit.

## Rationale

The 6-line diff only adds `"env": { "MEMELEX_MCP_PORT": "19998" }` overrides
to the `memelex-mcp` and `memelex-agent-tools-mcp` server entries. Port
`19998` is this workstation's local memelex instance port — committing it
would silently re-point other developers' MCP servers to a port that does
not exist on their machines (or, worse, collides with a different service).

No new servers added, no stale entries removed, no schema upgrade — purely
local-machine config drift.

## Instructions for Task 4

- Do NOT include `.mcp.json` in the `git add` list.
- Use explicit per-file `git add <path>` (no `git add -A` / `git add .`).
- Add this line to the commit message body:

  > `.mcp.json` intentionally left out of this commit — local-machine config drift (MEMELEX_MCP_PORT override).

## Post-cycle state

`.mcp.json` should remain dirty in `git status` after the cycle's commit.
This decision file itself is a cycle artifact and should also be left
unstaged (or deleted by retro).
