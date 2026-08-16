defmodule QuillEx.Assets do
  @moduledoc """
  Static assets compiled into the release.

  The editor face is IBM Plex Mono (SIL OFL, see
  assets/fonts/IBM_Plex_Mono/LICENSE.txt), bundled in every weight and its
  italics so styling — syntax highlighting, structural markup — can lean on
  weight and slant, not colour alone. `:ibm_plex_mono` is the Regular face
  the editor has always used; the others follow the `_<weight>[_italic]`
  pattern.
  """

  use Scenic.Assets.Static,
    otp_app: :quillex,
    alias: [
      ibm_plex_mono: "fonts/IBM_Plex_Mono/IBMPlexMono-Regular.ttf",
      ibm_plex_mono_italic: "fonts/IBM_Plex_Mono/IBMPlexMono-Italic.ttf",
      ibm_plex_mono_bold: "fonts/IBM_Plex_Mono/IBMPlexMono-Bold.ttf",
      ibm_plex_mono_bold_italic: "fonts/IBM_Plex_Mono/IBMPlexMono-BoldItalic.ttf",
      ibm_plex_mono_thin: "fonts/IBM_Plex_Mono/IBMPlexMono-Thin.ttf",
      ibm_plex_mono_thin_italic: "fonts/IBM_Plex_Mono/IBMPlexMono-ThinItalic.ttf",
      ibm_plex_mono_extralight: "fonts/IBM_Plex_Mono/IBMPlexMono-ExtraLight.ttf",
      ibm_plex_mono_extralight_italic: "fonts/IBM_Plex_Mono/IBMPlexMono-ExtraLightItalic.ttf",
      ibm_plex_mono_light: "fonts/IBM_Plex_Mono/IBMPlexMono-Light.ttf",
      ibm_plex_mono_light_italic: "fonts/IBM_Plex_Mono/IBMPlexMono-LightItalic.ttf",
      ibm_plex_mono_text: "fonts/IBM_Plex_Mono/IBMPlexMono-Text.ttf",
      ibm_plex_mono_text_italic: "fonts/IBM_Plex_Mono/IBMPlexMono-TextItalic.ttf",
      ibm_plex_mono_medium: "fonts/IBM_Plex_Mono/IBMPlexMono-Medium.ttf",
      ibm_plex_mono_medium_italic: "fonts/IBM_Plex_Mono/IBMPlexMono-MediumItalic.ttf",
      ibm_plex_mono_semibold: "fonts/IBM_Plex_Mono/IBMPlexMono-SemiBold.ttf",
      ibm_plex_mono_semibold_italic: "fonts/IBM_Plex_Mono/IBMPlexMono-SemiBoldItalic.ttf"
    ]
end
