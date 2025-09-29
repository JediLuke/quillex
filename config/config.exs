import Config

config :scenic, :assets, module: QuillEx.Assets

# Configure scenic_mcp port for Quillex (different from Flamelex to avoid conflicts)
config :scenic_mcp, 
  port: 9997,
  app_name: "Quillex"

config :event_bus,
  topics: [
    :quill_ex_actions,
    :quill_ex_user_input
  ]

config :logger, level: :info

import_config "#{Mix.env()}.exs"
