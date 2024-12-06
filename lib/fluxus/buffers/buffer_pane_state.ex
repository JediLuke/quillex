defmodule Quillex.GUI.Components.BufferPane.State do

  defstruct [
    frame: nil,
    font: nil,
    colors: nil,
    # Where we keep track of how much we've scrolled the buffer around
    scroll_acc: {0, 0},
    buf_ref: nil
  ]

  def new(%{
    frame: %Widgex.Frame{} = frame,
    buf_ref: %Quillex.Structs.BufState.BufRef{} = buf_ref
  }) do
    %__MODULE__{
      font: default_font(),
      frame: frame,
      colors: default_colors(),
      buf_ref: buf_ref
    }
  end

  def ibm_plex_mono do
    #TODO load fonts from somewhere logical
    TruetypeMetrics.load("./assets/fonts/IBM_Plex_Mono/IBMPlexMono-Regular.ttf")
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

  @typewriter %{
    text: :black,
    slate: :white
  }

  @cauldron %{
    text: :white,
    slate: :medium_slate_blue
  }

  def default_colors, do: @cauldron

end

#   defstruct [
#     # affects how we render the cursor
#     mode: nil,
#     # the font settings for this TextPad
#     font: nil,
#     # hold the list of LineOfText structs
#     lines: nil,
#     # how much margin we want to leave around the edges
#     margin: nil,
#     # maintains the cursor coords, note we just support single-cursor for now
#     cursor: %{
#       line: nil,
#       col: nil
#     },
#     opts: %{
#       alignment: :left,
#       wrap: :no_wrap,
#       scroll: %{
#         direction: :all,
#         # An accumulator for the amount of scroll
#         acc: {0, 0}
#       },
#       # toggles the display of line numbers in the left margin
#       show_line_nums?: false
#     }
#   ]
