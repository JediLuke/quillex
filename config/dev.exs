import Config

config :logger, level: :debug

# Configure scenic_mcp port for Quillex (different from Flamelex to avoid conflicts)
config :scenic_mcp,
  port: 9997,
  app_name: "Quillex"
