#!/usr/bin/env bash
# Launch the scenic-mcp server (stdio) for a coding agent.
#
# The server is the Node half of scenic_mcp_experimental; the Elixir half is
# already a dev/test dependency of quillex and listens on port 9997 (dev) or
# 9987 (test) once the app is running. The checkout lives beside quillex, as
# every other sibling of the constellation does, and its build output is not
# committed, so it has to be built once per machine:
#
#     cd ../scenic_mcp_experimental && npm install && npm run build
#
# Override the location with SCENIC_MCP_DIR if the checkout is elsewhere.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="${SCENIC_MCP_DIR:-$here/../../../scenic_mcp_experimental}"
server="$dir/dist/index.js"

if [ ! -f "$server" ] || [ ! -d "$dir/node_modules" ]; then
  echo "scenic-mcp: no build at $dir" >&2
  echo "scenic-mcp: run 'npm install && npm run build' there, or set SCENIC_MCP_DIR" >&2
  exit 1
fi

exec node "$server"
