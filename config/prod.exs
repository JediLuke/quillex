import Config

# The environment an actual user of the editor runs in — `bin/qlx` defaults to
# it. Nothing here listens on a socket: scenic_mcp is a dev/test-only
# dependency and Tidewave is gated on Mix.env() == :dev in Quillex.App. A text
# editor someone was handed has no business holding open ports.
config :logger, level: :warning
