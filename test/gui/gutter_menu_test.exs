defmodule Quillex.GUI.GutterMenuTest do
  use ExUnit.Case, async: true

  alias Quillex.GUI.GutterMenu

  @theme GutterMenu.theme(%{
           font: :ibm_plex_mono,
           dropdown_bg: {0, 0, 0},
           dropdown_border: {0, 0, 0},
           item_text_color: {255, 255, 255},
           item_hover_bg: {0, 0, 255},
           item_hover_text_color: {255, 255, 255}
         })

  @view {1000, 600}

  defp layout(menu) do
    rows = GutterMenu.rows(menu, 2)
    GutterMenu.bounds(menu, rows, @theme, @view)
  end

  defp row_middle(bounds, id), do: bounds.items[id].y + @theme.dropdown_item_height / 2

  test "opens at the click, pulled back inside the view near its edges" do
    menu = GutterMenu.new(%{line: 3, at: {100, 200}})
    assert %{x: 100, y: 200} = layout(menu)

    near_corner = GutterMenu.new(%{line: 3, at: {990, 590}})
    bounds = layout(near_corner)
    assert bounds.x + bounds.width <= 1000
    assert bounds.y + bounds.height <= 600
  end

  test "the fold-level row opens its list, then an option folds to that level" do
    menu = GutterMenu.new(%{line: 3, at: {100, 200}})
    bounds = layout(menu)
    control = {bounds.x + bounds.width - 20, row_middle(bounds, :gutter_fold_level)}
    assert GutterMenu.click(menu, bounds, @theme, control) == :toggle_select

    open = %{menu | select_expanded?: true}
    bounds = layout(open)
    select_y = bounds.items[:gutter_fold_level].y
    h = @theme.dropdown_item_height

    for level <- 1..5 do
      point = {bounds.x + bounds.width - 20, select_y + h * level + h / 2}
      assert GutterMenu.click(open, bounds, @theme, point) == {:fold_to_level, level}

      assert %{hovered: :gutter_fold_level, hovered_option: ^level} =
               GutterMenu.hover(open, bounds, @theme, point)
    end
  end

  test "clear all folds, and anything off the rows closes the menu" do
    menu = GutterMenu.new(%{line: 3, at: {100, 200}})
    bounds = layout(menu)

    assert GutterMenu.click(
             menu,
             bounds,
             @theme,
             {bounds.x + 20, row_middle(bounds, :gutter_clear_folds)}
           ) ==
             :unfold_all

    assert GutterMenu.click(menu, bounds, @theme, {5, 5}) == :close
    assert GutterMenu.click(menu, bounds, @theme, {bounds.x + 20, bounds.y + 1}) == :close
    assert %{hovered: nil} = GutterMenu.hover(menu, bounds, @theme, {5, 5})
  end
end
