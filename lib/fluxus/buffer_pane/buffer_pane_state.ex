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

  @doc """
  Metrics for the font Scenic is already rendering with.

  Read out of the compiled asset library rather than off disk. A path — even an
  absolute one — assumes the source tree is still sitting where it was at
  compile time, which is false the moment `qlx` adopts the shell's working
  directory, and false again inside a release that has been copied elsewhere.
  The library travels in the app's own priv directory, so it is always there.
  """
  def ibm_plex_mono do
    {:ok, {Scenic.Assets.Static.Font, %FontMetrics{} = metrics}} =
      Scenic.Assets.Static.meta(:ibm_plex_mono)

    {:ok, metrics}
  end

  def default_colors, do: @cauldron
end
