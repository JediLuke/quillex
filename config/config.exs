import Config

config :scenic, :assets, module: Quillex.Assets

# Direct-mode TextFields (the search pane's fields) paste through the widget
# library's clipboard. Point it at quillex's own so there is one clipboard,
# one config for it, and one file-backed stand-in under test.
config :scenic_widget_contrib, :clipboard_adapter, Quillex.Buffer.ContribClipboard

# scenic_mcp is configured in dev.exs and test.exs, not here: it's a dev/test
# dependency, and configuring an application that isn't in the build makes Mix
# warn loudly on every prod boot.

config :logger, level: :info

import_config "#{Mix.env()}.exs"
