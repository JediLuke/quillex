defmodule Quillex.GUI.PaletteTest do
  use ExUnit.Case, async: true

  alias Quillex.GUI.Palette

  @derivations [
    :text_field_colors,
    :tab_bar_theme,
    :icon_menu_theme,
    :side_nav_theme,
    :search_pane_theme,
    :search_bar_theme
  ]

  test "there are exactly five themes, and the default is one of them" do
    assert length(Palette.themes()) == 5
    assert Palette.default() in Palette.ids()
  end

  # A palette missing one token would not fail until the surface that reads it
  # happened to be drawn — a sidebar nobody opened, a status strip nobody
  # triggered. Deriving every component theme for every palette finds it here.
  test "every palette can drive every surface" do
    for id <- Palette.ids(), derivation <- @derivations do
      theme = apply(Palette, derivation, [Palette.get(id)])

      assert map_size(theme) > 0

      for {key, value} <- theme do
        assert value != nil, "#{id}.#{derivation} left #{key} unset"
      end
    end
  end

  test "every palette answers for every status severity and handle state" do
    for id <- Palette.ids() do
      palette = Palette.get(id)

      for severity <- [:info, :warning, :error] do
        assert is_tuple(Palette.status_color(palette, severity))
      end

      for handle_state <- [:idle, :hovered, :dragging] do
        assert {_fill, _stroke, _arrow} = Palette.handle_colors(palette, handle_state)
      end
    end
  end

  test "the default palette is the purple Quillex shipped with" do
    palette = Palette.get(Palette.default())
    assert palette.editor_bg == {123, 104, 238}
    assert palette.editor_fg == :white
  end

  test "an unknown theme id falls back to the default rather than crashing" do
    assert Palette.get(:no_such_theme) == Palette.get(Palette.default())
    refute Palette.known?(:no_such_theme)
  end

  test "every theme has a label" do
    for id <- Palette.ids(), do: assert(is_binary(Palette.label(id)))
  end
end
