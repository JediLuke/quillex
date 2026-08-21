defmodule Quillex.Utils.SideNavThemes do
  @moduledoc """
  Layout for the file navigator's SideNav.

  The *colours* come from `Quillex.GUI.Palette` — one palette drives the editor
  and every piece of chrome. What is left here is the sizing, and `dark/0` as
  the shape a palette is merged over so a missing key is still a valid theme.
  """

  @doc """
  The file navigator's theme, sized against the editor's text size.

  The sidebar is chrome, not content: it should read as secondary to the text
  being edited, so its label font is deliberately smaller than the buffer's.
  Colours come from `palette`; only the sizing is decided here.
  It still tracks `text_size` rather than being fixed, so bumping the editor
  font scales the whole UI instead of leaving the sidebar stranded.

  `@nav_text_ratio` is what makes it smaller; the floor keeps it legible if
  someone sets the editor to its 12pt minimum. Row height leaves room for the
  glyph plus breathing space.
  """
  @nav_text_ratio 0.7
  @nav_text_min 11

  def for_editor(text_size), do: for_editor(text_size, Quillex.GUI.Palette.get(Quillex.GUI.Palette.default()))

  @doc """
  The label size the file navigator uses, for a given chrome size.

  Exposed because the navigator is not the only piece of the sidebar: the
  search pane occupies the same slot, shows the same kind of thing — file
  names — and looked like a different application when it sized its own text
  independently. One number, one place.
  """
  def nav_font_size(text_size) when is_integer(text_size) and text_size > 0,
    do: max(@nav_text_min, round(text_size * @nav_text_ratio))

  def for_editor(text_size, palette) when is_integer(text_size) and text_size > 0 do
    font_size = nav_font_size(text_size)

    dark()
    |> Map.merge(Quillex.GUI.Palette.side_nav_theme(palette))
    |> Map.put(:font, :ibm_plex_mono)
    |> Map.put(:font_size, font_size)
    |> Map.put(:line_height, font_size + 6)
    |> Map.put(:item_height, font_size + 10)
  end

  @doc """
  The full shape of a SideNav theme, with the sizing this app wants and the
  original merlinex-inspired colours.

  A palette is merged over the colours; this exists so that a palette missing
  a key still yields a complete, drawable theme rather than a crash inside the
  widget's renderer.
  """
  def dark do
    %{
      # Colors - Dark theme (merlinex-inspired)
      # Dark blue-gray (list_bg)
      background: {35, 37, 47},
      # Light gray text
      text: {220, 220, 230},
      # Blue-tinted active background
      active_bg: {60, 80, 120},
      # Bright blue accent bar
      active_bar: {100, 160, 220},
      # Quiet neutral operation selection
      selection_bg: {48, 51, 62},
      # Slightly lighter hover
      hover_bg: {55, 58, 70},
      # Medium gray chevrons
      chevron: {140, 140, 150},
      # Blue focus ring
      focus_ring: {100, 160, 220},
      # Subtle border
      border: {50, 52, 62},
      # Clearly visible over the dark pane
      scrollbar_color: {185, 190, 205},
      # Drag-and-drop feedback. Green/red carry the meaning for most people, so
      # they are also the two most different in brightness against the pane —
      # the accept reads lighter than the background, the reject darker.
      drop_valid_bg: {52, 96, 70},
      drop_invalid_bg: {104, 48, 52},
      drop_text: {245, 246, 250},
      # The label riding the cursor: darker than any row so it reads as floating
      # above the tree rather than as part of it.
      ghost_bg: {24, 26, 34},
      ghost_text: {225, 228, 238},

      # Dimensions
      # Compact but readable
      item_height: 26,
      # Indentation per level
      indent: 14,
      font: :roboto,
      font_size: 13,
      line_height: 18,

      # Spacing
      padding_left: 10,
      padding_right: 10,
      item_spacing: 0,

      # Chevron
      chevron_size: 12,
      chevron_margin: 6
    }
  end

end
