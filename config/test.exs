import Config

config :logger, level: :warn

# Use a wider window for tests to prevent text wrapping
# Use :edit mode (notepad-style) for comprehensive text editing tests
config :quillex,
  test_window_size: {2000, 1200},
  default_buffer_mode: :edit

# Use different port for scenic_mcp in Quillex test environment
# Using 9987 to avoid conflicts with running apps (Quillex=9997, Flamelex=9999)
config :scenic_mcp, port: 9987
