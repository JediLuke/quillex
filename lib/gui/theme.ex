defmodule Quillex.GUI.Theme do
  @moduledoc "Application visual tokens shared by editor and navigation."

  def editor_font(size) when size in 12..32 do
    {:ok, {Scenic.Assets.Static.Font, metrics}} = Scenic.Assets.Static.meta(:ibm_plex_mono)
    %{name: :ibm_plex_mono, size: size, metrics: metrics}
  end

  @doc """
  How token classes are drawn — the STRUCTURAL scheme: weight, slant and
  underline carry the meaning, never colour, so it reads the same for every
  kind of colour vision and needs no palette. See `Quillex.Highlight` for
  the classes.
  """
  def highlight_styles do
    %{
      keyword: %{font: :ibm_plex_mono_bold},
      definition: %{font: :ibm_plex_mono_semibold},
      attribute: %{font: :ibm_plex_mono_medium_italic},
      comment: %{font: :ibm_plex_mono_light_italic},
      doc: %{font: :ibm_plex_mono_light},
      string: %{underline: true},
      number: %{font: :ibm_plex_mono_medium}
    }
  end

  def editor_colors do
    %{text: :white, slate: :medium_slate_blue}
  end
end
