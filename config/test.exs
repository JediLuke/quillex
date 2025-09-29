import Config

config :logger, level: :warn

# Use a wider window for tests to prevent text wrapping
config :quillex,
  test_window_size: {2000, 1200}

# Use different port for scenic_mcp in Quillex test environment
config :scenic_mcp, port: 9996
