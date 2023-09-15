defmodule QuillEx.GUI.Themes do
  @midnight_pallette %{
    # I made this one up...
    black_outliner: {40, 33, 40},
    # 2596be
    primary: {37, 150, 190},
    # 292931
    dark: {41, 41, 49},
    # 778899
    slate: {119, 136, 153},
    # a7a3bb
    gray: {167, 163, 187},
    # c1937a
    light_brown: {193, 147, 122},
    # 6c6d7b
    dark_gray: {108, 109, 123},
    # 8fb27b
    light_green: {143, 178, 123},
    # 28df28
    nuclear_green: {40, 233, 40},
    # 78584f
    brown: {120, 88, 79},
    # 4b4d5c
    rly_dark_gray: {75, 77, 92},
    # 533432
    red_brown: {83, 52, 50},
    # 556c4d
    green: {85, 108, 77},
    # 6694da
    blue: {102, 148, 218}
  }

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

  def midnight_shadow,
    do: %{
      text: @midnight_pallette.nuclear_green,
      background: @midnight_pallette.dark_gray,
      border: @midnight_pallette.rly_dark_gray,
      active: @midnight_pallette.light_green,
      thumb: @midnight_pallette.red_brown,
      focus: @midnight_pallette.blue,
      highlight: @midnight_pallette.primary
    }

  # def midnight_shadow,
  #   do: %{
  #     # 9ca5b6
  #     text: {156, 165, 182},
  #     # 282b33
  #     background: {40, 43, 51},
  #     # 202329
  #     border: {32, 35, 41},
  #     # 6694da
  #     focus: {102, 148, 218},
  #     # e3c18a
  #     highlight: {227, 193, 138}
  #   }
end
