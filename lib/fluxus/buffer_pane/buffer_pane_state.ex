defmodule Quillex.GUI.Components.BufferPane.State do
  @moduledoc """
  Minimal state for BufferPane - most state is now handled by TextField.
  This just holds colors and provides font configuration helper.
  """

  defstruct [
    colors: nil,
    font: nil,
    active?: true
  ]

  @cauldron %{
    text: :white,
    slate: :medium_slate_blue
  }

  def new(args) do
    %__MODULE__{
      font: default_font(),
      colors: default_colors(),
      active?: Map.get(args, :active?, true)
    }
  end

  def default_font do
    font_size = 24
    font_name = :ibm_plex_mono

    {:ok, font_metrics} = ibm_plex_mono()

    Quillex.Structs.BufState.Font.new(%{
      name: font_name,
      size: font_size,
      metrics: font_metrics
    })
  end

  def ibm_plex_mono do
    # Load fonts from file
    TruetypeMetrics.load("./assets/fonts/IBM_Plex_Mono/IBMPlexMono-Regular.ttf")
  end

  def default_colors, do: @cauldron
end
