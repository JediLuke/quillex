defmodule QuillEx.Assets do
  use Scenic.Assets.Static,
    otp_app: :quill_ex,
    alias: [
      ibm_plex_mono: "fonts/IBMPlexMono-Regular.ttf"
    ]
end