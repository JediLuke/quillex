defmodule QuillEx.Assets do
  use Scenic.Assets.Static,
    otp_app: :quill_ex,
    alias: [
      ibm_plex_mono: "fonts/IBMPlexMono-Regular.ttf",
      iosevka: "fonts/ttf-iosevka-etoile-15.6.3/iosevka-etoile-regular.ttf",
      source_code_pro: "fonts/SourceCodePro-Regular.ttf",
      fire_code: "fonts/FiraCode-Regular.ttf",
      bitter: "fonts/Bitter-Regular.ttf",
    ]
end
