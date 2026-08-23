import Config

config :scenic, :assets, module: Quillex.Assets

# scenic_mcp is configured in dev.exs and test.exs, not here: it's a dev/test
# dependency, and configuring an application that isn't in the build makes Mix
# warn loudly on every prod boot.

config :logger, level: :info

import_config "#{Mix.env()}.exs"
