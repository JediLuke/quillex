import Config

config :logger, level: :warn

# Use a wider window for tests to prevent text wrapping
config :quillex,
  test_window_size: {2000, 1200}
