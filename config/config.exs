import Config

config :scenic, :assets,
  module: QuillEx.Assets

config :event_bus,
  # most events & input gets processed through here
  topics: [:general]

config :logger, level: :info

import_config "#{Mix.env()}.exs"