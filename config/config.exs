import Config

config :scenic,
       :assets,
       module: QuillEx.Assets

config :event_bus,
  # most events & input gets processed through here
  topics: [:general]

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
#     import_config "prod.exs"
