import Config

# The environment an actual user of the editor runs in — `bin/qlx` defaults to
# it. Nothing here listens on a socket: scenic_mcp is a dev/test-only
# dependency. A text editor someone was handed has no business holding ports.
config :logger, level: :warning
