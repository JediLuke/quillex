defmodule Quillex.GUI.Palette do
  @moduledoc """
  The single source of colour for the whole application.

  Every surface Quillex draws — the editor, the tab bar, the menubar, the
  sidebar, the search pane, the status strip — takes its colours from one of
  the palettes here. A light buffer inside a dark sidebar reads as broken, not
  as a theme, so the scope is deliberately everything at once.

  Syntax highlighting is **not** here. It is structural — weight, slant and
  underline — so it needs no palette and works for every kind of colour vision.
  See `Quillex.GUI.Theme.highlight_styles/0`.

  ## The palettes

  Five, and this is the whole list:

  | id | name |
  |---|---|
  | `:alchemical_dark` | Alchemical Wedding (Dark) — the default |
  | `:alchemical_light` | Alchemical Wedding (Light) |
  | `:solarized_dark` | Solarized Dark |
  | `:solarized_light` | Solarized Light |
  | `:high_contrast` | High Contrast |

  ## Tokens, then components

  A palette is a flat map of *semantic* tokens — `editor_bg`, `chrome_fg`,
  `accent` — and the `*_theme/1` functions turn those into the shape each
  widget expects. Components stay generic (they know nothing about Quillex's
  palettes) and Quillex keeps one place to change a colour.

  `:alchemical_dark` reproduces exactly what Quillex looked like before themes
  existed, so choosing the default is a no-op rather than a redesign.
  """

  @themes [
    {:alchemical_dark, "Alchemical Wedding (Dark)"},
    {:alchemical_light, "Alchemical Wedding (Light)"},
    {:solarized_dark, "Solarized Dark"},
    {:solarized_light, "Solarized Light"},
    {:high_contrast, "High Contrast"}
  ]

  @doc "Every theme, as `{id, label}`, in menu order."
  def themes, do: @themes

  @doc "The theme ids, for validation."
  def ids, do: Enum.map(@themes, &elem(&1, 0))

  @doc "The default theme."
  def default, do: :alchemical_dark

  @doc "A theme's display name."
  def label(id) do
    {^id, label} = Enum.find(@themes, fn {theme_id, _} -> theme_id == id end)
    label
  end

  @doc "Is this a known theme id?"
  def known?(id), do: id in ids()

  # ── The palettes ──────────────────────────────────────────────────────────

  @doc "The token map for a theme. Unknown ids fall back to the default."
  def get(id) do
    if known?(id), do: tokens(id), else: tokens(default())
  end

  # The purple. These are the exact values Quillex shipped with before themes
  # existed — medium slate blue behind the text, white on top of it.
  defp tokens(:alchemical_dark) do
    %{
      editor_bg: {123, 104, 238},
      editor_fg: :white,
      cursor: :white,
      line_numbers: {255, 255, 255, 85},
      border: {80, 80, 100, 180},
      focused_border: {255, 215, 0},
      selection: {70, 130, 180, 180},
      search_match: {255, 255, 0, 120},
      search_current_match: {255, 165, 0, 180},
      matching_brace: {255, 215, 0},
      cursor_guide: {255, 215, 0, 30},
      scrollbar_track: {80, 80, 80, 200},
      scrollbar_thumb: {160, 160, 160, 255},
      chrome_bg: {45, 45, 45},
      chrome_selected_bg: {30, 30, 30},
      chrome_hover_bg: {60, 60, 60},
      chrome_fg: {180, 180, 180},
      chrome_selected_fg: {255, 255, 255},
      chrome_separator: {60, 60, 60},
      dropdown_bg: {50, 50, 50},
      dropdown_border: {70, 70, 70},
      dropdown_fg: {220, 220, 220},
      accent: {0, 150, 255},
      accent_fg: {255, 255, 255},
      pane_bg: {35, 37, 47},
      pane_fg: {220, 220, 230},
      pane_dim: {140, 140, 150},
      pane_hover_bg: {55, 58, 70},
      pane_selection_bg: {48, 51, 62},
      pane_active_bg: {60, 80, 120},
      pane_border: {50, 52, 62},
      pane_scrollbar: {185, 190, 205},
      field_bg: {22, 22, 26},
      field_border: {80, 80, 96},
      match_highlight_bg: {96, 78, 30},
      status_info: {60, 130, 70},
      status_warning: {170, 100, 30},
      status_error: {160, 40, 40},
      status_fg: :white,
      error_fg: {240, 130, 130},
      drop_valid_bg: {52, 96, 70},
      drop_invalid_bg: {104, 48, 52},
      drop_text: {245, 246, 250},
      ghost_bg: {24, 26, 34},
      ghost_text: {225, 228, 238},
      handle_bg: {55, 60, 72},
      handle_stroke: {105, 115, 135},
      handle_arrow: {180, 188, 205},
      handle_hover_bg: {72, 91, 126},
      handle_hover_stroke: {150, 174, 220},
      handle_hover_arrow: {225, 232, 245},
      handle_active_bg: {205, 216, 236},
      handle_active_stroke: {235, 241, 250},
      handle_active_arrow: {42, 52, 72}
    }
  end

  # The same identity, light surfaces: the violet becomes a wash rather than a
  # field, and everything that sat on top of it flips.
  defp tokens(:alchemical_light) do
    %{
      editor_bg: {238, 234, 252},
      editor_fg: {38, 32, 60},
      cursor: {70, 50, 160},
      line_numbers: {90, 80, 130, 150},
      border: {180, 172, 214, 200},
      focused_border: {123, 104, 238},
      selection: {123, 104, 238, 90},
      search_match: {250, 220, 90, 150},
      search_current_match: {245, 160, 40, 190},
      matching_brace: {110, 80, 200},
      cursor_guide: {123, 104, 238, 28},
      scrollbar_track: {200, 195, 220, 200},
      scrollbar_thumb: {130, 120, 175, 255},
      chrome_bg: {236, 233, 245},
      chrome_selected_bg: {250, 249, 255},
      chrome_hover_bg: {224, 219, 240},
      chrome_fg: {80, 72, 110},
      chrome_selected_fg: {32, 26, 56},
      chrome_separator: {208, 202, 228},
      dropdown_bg: {250, 249, 255},
      dropdown_border: {206, 200, 228},
      dropdown_fg: {50, 44, 78},
      accent: {96, 76, 214},
      accent_fg: {255, 255, 255},
      pane_bg: {244, 242, 252},
      pane_fg: {46, 40, 72},
      pane_dim: {112, 104, 142},
      pane_hover_bg: {230, 226, 245},
      pane_selection_bg: {222, 217, 240},
      pane_active_bg: {206, 198, 240},
      pane_border: {214, 208, 234},
      pane_scrollbar: {138, 128, 178},
      field_bg: {255, 255, 255},
      field_border: {198, 191, 224},
      match_highlight_bg: {250, 224, 150},
      status_info: {58, 122, 74},
      status_warning: {176, 110, 24},
      status_error: {172, 46, 46},
      status_fg: :white,
      error_fg: {170, 40, 50},
      drop_valid_bg: {188, 226, 198},
      drop_invalid_bg: {240, 196, 198},
      drop_text: {32, 26, 56},
      ghost_bg: {255, 255, 255},
      ghost_text: {46, 40, 72},
      handle_bg: {222, 217, 240},
      handle_stroke: {180, 172, 214},
      handle_arrow: {80, 72, 110},
      handle_hover_bg: {196, 186, 236},
      handle_hover_stroke: {130, 116, 208},
      handle_hover_arrow: {40, 32, 78},
      handle_active_bg: {96, 76, 214},
      handle_active_stroke: {60, 44, 160},
      handle_active_arrow: {255, 255, 255}
    }
  end

  # Ethan Schoonover's palette, base03 ground.
  defp tokens(:solarized_dark) do
    %{
      editor_bg: {0, 43, 54},
      editor_fg: {131, 148, 150},
      cursor: {147, 161, 161},
      line_numbers: {88, 110, 117, 200},
      border: {7, 54, 66, 220},
      focused_border: {38, 139, 210},
      selection: {38, 139, 210, 110},
      search_match: {181, 137, 0, 130},
      search_current_match: {203, 75, 22, 190},
      matching_brace: {42, 161, 152},
      cursor_guide: {88, 110, 117, 45},
      scrollbar_track: {7, 54, 66, 220},
      scrollbar_thumb: {88, 110, 117, 255},
      chrome_bg: {7, 54, 66},
      chrome_selected_bg: {0, 43, 54},
      chrome_hover_bg: {18, 66, 78},
      chrome_fg: {131, 148, 150},
      chrome_selected_fg: {253, 246, 227},
      chrome_separator: {0, 43, 54},
      dropdown_bg: {7, 54, 66},
      dropdown_border: {0, 43, 54},
      dropdown_fg: {147, 161, 161},
      accent: {38, 139, 210},
      accent_fg: {253, 246, 227},
      pane_bg: {0, 36, 46},
      pane_fg: {131, 148, 150},
      pane_dim: {88, 110, 117},
      pane_hover_bg: {7, 54, 66},
      pane_selection_bg: {10, 60, 72},
      pane_active_bg: {14, 78, 94},
      pane_border: {7, 54, 66},
      pane_scrollbar: {101, 123, 131},
      field_bg: {0, 30, 38},
      field_border: {7, 54, 66},
      match_highlight_bg: {101, 76, 0},
      status_info: {42, 161, 152},
      status_warning: {181, 137, 0},
      status_error: {220, 50, 47},
      status_fg: {0, 43, 54},
      error_fg: {220, 50, 47},
      drop_valid_bg: {24, 82, 72},
      drop_invalid_bg: {96, 34, 32},
      drop_text: {253, 246, 227},
      ghost_bg: {0, 30, 38},
      ghost_text: {147, 161, 161},
      handle_bg: {7, 54, 66},
      handle_stroke: {88, 110, 117},
      handle_arrow: {147, 161, 161},
      handle_hover_bg: {14, 78, 94},
      handle_hover_stroke: {38, 139, 210},
      handle_hover_arrow: {253, 246, 227},
      handle_active_bg: {38, 139, 210},
      handle_active_stroke: {147, 161, 161},
      handle_active_arrow: {0, 43, 54}
    }
  end

  # Its matched pair, base3 ground.
  defp tokens(:solarized_light) do
    %{
      editor_bg: {253, 246, 227},
      editor_fg: {101, 123, 131},
      cursor: {88, 110, 117},
      line_numbers: {147, 161, 161, 220},
      border: {238, 232, 213, 240},
      focused_border: {38, 139, 210},
      selection: {38, 139, 210, 80},
      search_match: {181, 137, 0, 110},
      search_current_match: {203, 75, 22, 160},
      matching_brace: {42, 161, 152},
      cursor_guide: {147, 161, 161, 40},
      scrollbar_track: {238, 232, 213, 240},
      scrollbar_thumb: {147, 161, 161, 255},
      chrome_bg: {238, 232, 213},
      chrome_selected_bg: {253, 246, 227},
      chrome_hover_bg: {245, 239, 220},
      chrome_fg: {101, 123, 131},
      chrome_selected_fg: {7, 54, 66},
      chrome_separator: {225, 219, 200},
      dropdown_bg: {253, 246, 227},
      dropdown_border: {225, 219, 200},
      dropdown_fg: {88, 110, 117},
      accent: {38, 139, 210},
      accent_fg: {253, 246, 227},
      pane_bg: {245, 239, 220},
      pane_fg: {88, 110, 117},
      pane_dim: {147, 161, 161},
      pane_hover_bg: {238, 232, 213},
      pane_selection_bg: {232, 226, 206},
      pane_active_bg: {212, 226, 236},
      pane_border: {225, 219, 200},
      pane_scrollbar: {131, 148, 150},
      field_bg: {253, 246, 227},
      field_border: {225, 219, 200},
      match_highlight_bg: {247, 226, 158},
      status_info: {42, 161, 152},
      status_warning: {181, 137, 0},
      status_error: {220, 50, 47},
      status_fg: {253, 246, 227},
      error_fg: {203, 75, 22},
      drop_valid_bg: {186, 224, 214},
      drop_invalid_bg: {244, 200, 198},
      drop_text: {7, 54, 66},
      ghost_bg: {253, 246, 227},
      ghost_text: {88, 110, 117},
      handle_bg: {238, 232, 213},
      handle_stroke: {147, 161, 161},
      handle_arrow: {88, 110, 117},
      handle_hover_bg: {212, 226, 236},
      handle_hover_stroke: {38, 139, 210},
      handle_hover_arrow: {7, 54, 66},
      handle_active_bg: {38, 139, 210},
      handle_active_stroke: {7, 54, 66},
      handle_active_arrow: {253, 246, 227}
    }
  end

  # Black ground, pure-channel accents. Pairs with the colour-blind-safe
  # structural syntax marking: nothing here relies on hue to be legible.
  defp tokens(:high_contrast) do
    %{
      editor_bg: {0, 0, 0},
      editor_fg: {255, 255, 255},
      cursor: {255, 255, 0},
      line_numbers: {200, 200, 200, 255},
      border: {255, 255, 255, 255},
      focused_border: {255, 255, 0},
      selection: {0, 90, 255, 200},
      search_match: {255, 255, 0, 160},
      search_current_match: {255, 128, 0, 230},
      matching_brace: {0, 255, 255},
      cursor_guide: {255, 255, 255, 40},
      scrollbar_track: {40, 40, 40, 255},
      scrollbar_thumb: {255, 255, 255, 255},
      chrome_bg: {0, 0, 0},
      chrome_selected_bg: {40, 40, 40},
      chrome_hover_bg: {60, 60, 60},
      chrome_fg: {230, 230, 230},
      chrome_selected_fg: {255, 255, 0},
      chrome_separator: {255, 255, 255},
      dropdown_bg: {0, 0, 0},
      dropdown_border: {255, 255, 255},
      dropdown_fg: {255, 255, 255},
      accent: {255, 255, 0},
      accent_fg: {0, 0, 0},
      pane_bg: {0, 0, 0},
      pane_fg: {255, 255, 255},
      pane_dim: {200, 200, 200},
      pane_hover_bg: {60, 60, 60},
      pane_selection_bg: {40, 40, 40},
      pane_active_bg: {0, 70, 160},
      pane_border: {255, 255, 255},
      pane_scrollbar: {255, 255, 255},
      field_bg: {0, 0, 0},
      field_border: {255, 255, 255},
      match_highlight_bg: {120, 90, 0},
      status_info: {0, 110, 60},
      status_warning: {150, 90, 0},
      status_error: {170, 0, 0},
      status_fg: {255, 255, 255},
      error_fg: {255, 120, 120},
      drop_valid_bg: {0, 110, 60},
      drop_invalid_bg: {170, 0, 0},
      drop_text: {255, 255, 255},
      ghost_bg: {0, 0, 0},
      ghost_text: {255, 255, 0},
      handle_bg: {0, 0, 0},
      handle_stroke: {255, 255, 255},
      handle_arrow: {255, 255, 255},
      handle_hover_bg: {60, 60, 60},
      handle_hover_stroke: {255, 255, 0},
      handle_hover_arrow: {255, 255, 0},
      handle_active_bg: {255, 255, 0},
      handle_active_stroke: {255, 255, 255},
      handle_active_arrow: {0, 0, 0}
    }
  end

  # ── Component themes ──────────────────────────────────────────────────────

  @doc "The `colors` map a `ScenicWidgets.TextField` takes."
  def text_field_colors(p) do
    %{
      text: p.editor_fg,
      background: p.editor_bg,
      cursor: p.cursor,
      line_numbers: p.line_numbers,
      border: p.border,
      focused_border: p.focused_border,
      selection: p.selection,
      search_match: p.search_match,
      search_current_match: p.search_current_match,
      matching_brace: p.matching_brace,
      cursor_guide: p.cursor_guide,
      scrollbar_track: p.scrollbar_track,
      scrollbar_thumb: p.scrollbar_thumb
    }
  end

  @doc "Colour half of a `ScenicWidgets.TabBar` theme; the caller adds sizes."
  def tab_bar_theme(p) do
    %{
      background: p.chrome_bg,
      tab_background: p.chrome_bg,
      tab_hover_background: p.chrome_hover_bg,
      tab_selected_background: p.chrome_selected_bg,
      text_color: p.chrome_fg,
      text_selected_color: p.chrome_selected_fg,
      close_button_color: p.chrome_fg,
      close_button_hover_color: p.chrome_selected_fg,
      selection_indicator_color: p.accent,
      separator_color: p.chrome_separator,
      drop_indicator_color: p.accent,
      tab_drag_background: p.chrome_hover_bg
    }
  end

  @doc "Colour half of a `ScenicWidgets.IconMenu` theme."
  def icon_menu_theme(p) do
    %{
      background: p.chrome_bg,
      icon_color: p.chrome_fg,
      icon_hover_color: p.chrome_selected_fg,
      icon_active_color: p.chrome_selected_fg,
      icon_hover_bg: p.chrome_hover_bg,
      icon_active_bg: p.chrome_selected_bg,
      dropdown_bg: p.dropdown_bg,
      dropdown_border: p.dropdown_border,
      item_hover_bg: p.accent,
      item_text_color: p.dropdown_fg,
      item_hover_text_color: p.accent_fg
    }
  end

  @doc "Colour half of a `ScenicWidgets.SideNav` theme."
  def side_nav_theme(p) do
    %{
      background: p.pane_bg,
      text: p.pane_fg,
      active_bg: p.pane_active_bg,
      active_bar: p.accent,
      selection_bg: p.pane_selection_bg,
      hover_bg: p.pane_hover_bg,
      chevron: p.pane_dim,
      focus_ring: p.accent,
      border: p.pane_border,
      scrollbar_color: p.pane_scrollbar,
      drop_valid_bg: p.drop_valid_bg,
      drop_invalid_bg: p.drop_invalid_bg,
      drop_text: p.drop_text,
      ghost_bg: p.ghost_bg,
      ghost_text: p.ghost_text
    }
  end

  @doc "Colour half of a `ScenicWidgets.SearchPane` theme."
  def search_pane_theme(p) do
    %{
      background: p.pane_bg,
      header_background: p.pane_hover_bg,
      border: p.pane_border,
      text: p.pane_fg,
      dim_text: p.pane_dim,
      heading: p.pane_dim,
      field_background: p.field_bg,
      field_border: p.field_border,
      field_focus_border: p.accent,
      match_highlight: p.match_highlight_bg,
      match_text: p.pane_fg,
      row_hover: p.pane_hover_bg,
      button_background: p.pane_selection_bg,
      button_active: p.accent,
      button_text: p.pane_fg,
      error_text: p.error_fg,
      scrollbar_color: p.pane_scrollbar
    }
  end

  @doc "Colour half of a `ScenicWidgets.SearchBar` theme."
  def search_bar_theme(p) do
    %{
      background: p.chrome_bg,
      input_background: p.field_bg,
      text: p.chrome_selected_fg,
      placeholder: p.chrome_fg,
      border: p.field_border,
      button_bg: p.chrome_hover_bg,
      button_hover: p.chrome_selected_bg,
      match_highlight: p.accent
    }
  end

  @doc "The background of the transient status strip, by severity."
  def status_color(p, :warning), do: p.status_warning
  def status_color(p, :error), do: p.status_error
  def status_color(p, _info), do: p.status_info

  @doc """
  The file navigator's resize handle: `{fill, stroke, arrow}` for whichever of
  its three states it is in.
  """
  def handle_colors(p, :dragging), do: {p.handle_active_bg, p.handle_active_stroke, p.handle_active_arrow}
  def handle_colors(p, :hovered), do: {p.handle_hover_bg, p.handle_hover_stroke, p.handle_hover_arrow}
  def handle_colors(p, :idle), do: {p.handle_bg, p.handle_stroke, p.handle_arrow}
end
