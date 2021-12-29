defmodule QuillEx.GUI.Structs.Frame do
  @moduledoc """
  Struct which holds relevant data for rendering a buffer frame status bar.
  """
  require Logger


  defmodule Dimensions do
    defstruct [width: 0, height: 0]

    def new(width: w, height: h), do: %__MODULE__{width: w, height: h}
    def new(%{width: w, height: h}), do: %__MODULE__{width: w, height: h}
    def new({w, h}), do: %__MODULE__{width: w, height: h}
  end


  defstruct [
    pin:          {0, 0},         # The {x, y} of the top-left of this Frame
    size:         nil,            # How large in {width, height} this Frame is
    dimensions:   nil,            # a %Dimensions{} struct, specifying the height and width of the frame
    margin: %{
        top: 0,
        right: 0,
        bottom: 0,
        left: 0 },
    label:        nil,            # an optional label, usually used to render a footer bar
    opts:         %{}             # A map to hold options, e.g. %{render_footer?: true}
  ]


  def new(%Scenic.ViewPort{size: {w, h}}) do
    Logger.debug "constructing a new %Frame{} the size of the ViewPort."
    %__MODULE__{
      pin: {0, 0},
      size: {w, h},
      dimensions: Dimensions.new(width: w, height: h)
    }
  end

  def new([pin: {x, y}, size: {w, h}]) do
    %__MODULE__{
      pin: {x, y},
      size: {w, h},
      dimensions: Dimensions.new(width: w, height: h)
    }
  end


  # def set_margin(frame, %{top: t, left: l}) do
  #     %{frame|
  #         margin: %{
  #           top: t,
  #           right: 0,
  #           bottom: 0,
  #           left: l
  #         }
  #     }
  # end

end