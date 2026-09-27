defmodule Quillex.GUI.GutterMenu do
  @moduledoc """
  The fold menu that opens on a right-click in the buffer's line-number gutter.

  It used to live inside the TextField. It is Quillex's menu, not the text
  field's: which commands it offers, and that they drive the shared fold-level
  setting, are decisions this editor makes. The TextField now only reports the
  right-click (`{:gutter_context_menu, id, %{line:, at:}}`) and RootScene draws
  this over it, the way it draws the tab context menu.

  Everything here is pure: rows, theme, geometry and what a pointer at a point
  means. The root scene keeps the menu map in its state and does the drawing,
  the input capture and the dispatch.

  The menu map is `%{at: {x, y}, line: line, hovered: row_id | nil,
  hovered_option: level | nil, select_expanded?: boolean}`.
  """

  alias ScenicWidgets.Menu.Dropdown
  alias ScenicWidgets.Menu.Model.{Item, Select}

  @levels 1..5

  def new(%{line: line, at: {_x, _y} = at}) do
    %{at: at, line: line, hovered: nil, hovered_option: nil, select_expanded?: false}
  end

  def rows(menu, fold_level) do
    [
      %Select{
        id: :gutter_fold_level,
        label: "Set Fold Level",
        value: fold_level,
        options: Enum.map(@levels, &{&1, "Level #{&1}"}),
        option_width: 90,
        closed_caret: :left,
        expanded?: menu.select_expanded?
      },
      %Item{id: :gutter_clear_folds, label: "Clear All Folds"}
    ]
  end

  @doc """
  The dropdown theme: the one the menubar's panels use, with the few sizes a
  menubar never needed set to what this menu has always had.
  """
  def theme(menu_theme) do
    Map.merge(
      %{
        dropdown_font_size: 14,
        dropdown_item_height: 30,
        dropdown_divider_height: 10,
        dropdown_padding: 4,
        dropdown_width: 240,
        dropdown_column_gap: 16
      },
      menu_theme
    )
  end

  @doc """
  Where the panel sits: at the click, pulled back inside the viewport when the
  click was too near its right or bottom edge.
  """
  def bounds(menu, rows, theme, {view_width, view_height}) do
    %{at: {click_x, click_y}} = menu
    width = theme.dropdown_width
    height = Dropdown.content_height(rows, theme)
    x = min(click_x, max(view_width - width, 0))
    y = min(click_y, max(view_height - height, 0))

    Dropdown.layout(rows, theme, x: x, y: y, width: width, max_height: view_height - y)
  end

  def render(graph, menu, rows, theme, bounds) do
    Dropdown.render(graph, rows, bounds,
      theme: theme,
      hovered: menu.hovered,
      hovered_select_option: menu.hovered_option,
      show_shortcuts: false,
      id: :gutter_context_menu
    )
  end

  @doc "The menu with its hover moved to whatever is under `point`."
  def hover(menu, bounds, theme, point) do
    {hovered, option} =
      case Dropdown.row_at(bounds, point) do
        {:gutter_fold_level, {_x, local_y}} ->
          {:gutter_fold_level, option_at(menu, theme, local_y)}

        {id, _local} ->
          {id, nil}

        _panel_or_outside ->
          {nil, nil}
      end

    %{menu | hovered: hovered, hovered_option: option}
  end

  @doc """
  What a left-click at `point` does: `{:fold_to_level, n}` or `:unfold_all`
  close the menu and act, `:toggle_select` opens or shuts the level list, and
  anything else (the panel's padding included) is `:close`.
  """
  def click(menu, bounds, theme, point) do
    case Dropdown.row_at(bounds, point) do
      {:gutter_fold_level, {_x, local_y}} ->
        case option_at(menu, theme, local_y) do
          nil -> :toggle_select
          level -> {:fold_to_level, level}
        end

      {:gutter_clear_folds, _local} ->
        :unfold_all

      _panel_or_outside ->
        :close
    end
  end

  # With the level list open, the select row is its closed control followed by
  # one option per row height; a point below the control is an option.
  defp option_at(%{select_expanded?: false}, _theme, _local_y), do: nil

  defp option_at(%{select_expanded?: true}, theme, local_y) do
    option = floor(local_y / theme.dropdown_item_height)
    if option in @levels, do: option
  end
end
