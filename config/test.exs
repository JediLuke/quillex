import Config

config :logger, level: :warning

config :quillex, :clipboard_commands,
  unix: [
    copy: {"tee", ["/tmp/quillex_test_clipboard"]},
    paste: {"cat", ["/tmp/quillex_test_clipboard"]}
  ]

# Use a wider window for tests to prevent text wrapping
# Use :edit mode (notepad-style) for comprehensive text editing tests
config :quillex,
  test_window_size: {2000, 1200},
  default_buffer_mode: :edit

# Use different port for scenic_mcp in Quillex test environment
# Using 9987 to avoid conflicts with running apps (Quillex=9997, Flamelex=9999)
config :scenic_mcp,
  port: 9987,
  app_name: "Quillex"

# The spex reporter is quiet unless `mix spex --verbose` asks for the
# given/when/then narration. The task only ever SETS quiet (to true, when
# --verbose is absent) and reads it with a default of true, so without this
# line --verbose changes nothing. `scripts/run_demo --short` relies on it: the
# short demo's narration is the reporter.
config :sexy_spex, quiet: false
