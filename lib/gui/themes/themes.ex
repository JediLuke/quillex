defmodule QuillEx.GUI.Themes do
  def scenic_light,
    do: %{
      text: :black,
      background: :white,
      border: :dark_grey,
      active: {215, 215, 215},
      thumb: :cornflower_blue,
      focus: :blue,
      highlight: :saddle_brown
    }
end
