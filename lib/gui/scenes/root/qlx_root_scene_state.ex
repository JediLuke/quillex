
defmodule QuillEx.RootScene.State do
  use StructAccess

  defstruct [
    font: nil,
    tabs: [],
    toolbar: nil,
    buffers: []
  ]

  def new(%{buffers: buffers}) when is_list(buffers) do
    # dont show the tab-bar if we only have one buffer open
    tabs = if length(buffers) > 1, do: buffers, else: []

    %__MODULE__{
      font: default_font(),
      tabs: tabs,
      toolbar: %{
        height: 50
      },
      buffers: buffers
    }
  end

  def default_font do
    font_size = 24
    font_name = :ibm_plex_mono

    {:ok, font_metrics} = TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")

    Quillex.Structs.BufState.Font.new(%{
      name: font_name,
      size: font_size,
      metrics: font_metrics
    })
  end
end
