defmodule QuillEx.Assets do
  use Scenic.Assets.Static,
    otp_app: :quillex,
    alias: [
      ibm_plex_mono: "fonts/IBM_Plex_Mono/IBMPlexMono-Regular.ttf"
    ]
end
