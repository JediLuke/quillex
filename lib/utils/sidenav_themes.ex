defmodule Quillex.Utils.SideNavThemes do
  @moduledoc """
  Theme definitions for SideNav component in Quillex.

  Provides both a bare-bones default theme and a polished dark theme
  based on the merlinex app styling conventions.
  """

  @doc """
  The file navigator's theme, sized against the editor's text size.

  The sidebar is chrome, not content: it should read as secondary to the text
  being edited, so its label font is deliberately smaller than the buffer's.
  It still tracks `text_size` rather than being fixed, so bumping the editor
  font scales the whole UI instead of leaving the sidebar stranded.

  `@nav_text_ratio` is what makes it smaller; the floor keeps it legible if
  someone sets the editor to its 12pt minimum. Row height leaves room for the
  glyph plus breathing space.
  """
  @nav_text_ratio 0.7
  @nav_text_min 11

  def for_editor(text_size) when is_integer(text_size) and text_size > 0 do
    font_size = max(@nav_text_min, round(text_size * @nav_text_ratio))

    dark()
    |> Map.put(:font, :ibm_plex_mono)
    |> Map.put(:font_size, font_size)
    |> Map.put(:line_height, font_size + 6)
    |> Map.put(:item_height, font_size + 10)
  end

  @doc """
  Dark theme based on merlinex app styling.

  Features:
  - Dark blue-gray backgrounds
  - Subtle hover/active states
  - Clean, professional appearance
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

  @doc """
  Bare bones theme - minimal styling, very light weight.

  Good for debugging or when you want no visual distractions.
  """
  def bare_bones do
    %{
      # Minimal colors
      background: {45, 45, 50},
      text: :white,
      active_bg: {70, 70, 80},
      active_bar: :cyan,
      selection_bg: {58, 58, 66},
      hover_bg: {55, 55, 60},
      chevron: {150, 150, 150},
      focus_ring: :cyan,
      border: {60, 60, 65},
      scrollbar_color: {190, 190, 200},

      # Dimensions
      item_height: 24,
      indent: 12,
      font: :roboto,
      font_size: 12,
      line_height: 16,

      # Spacing
      padding_left: 8,
      padding_right: 8,
      item_spacing: 0,

      # Chevron
      chevron_size: 10,
      chevron_margin: 4
    }
  end

  @doc """
  Light theme - HexDocs-inspired light appearance.

  For users who prefer light mode.
  """
  def light do
    %{
      # Light colors
      background: {250, 250, 252},
      text: {34, 34, 34},
      active_bg: {229, 242, 255},
      active_bar: {76, 86, 106},
      selection_bg: {214, 218, 224},
      hover_bg: {240, 240, 245},
      chevron: {80, 80, 80},
      focus_ring: {0, 112, 214},
      border: {220, 220, 225},
      scrollbar_color: {105, 110, 125},

      # Dimensions
      item_height: 28,
      indent: 16,
      font: :roboto,
      font_size: 14,
      line_height: 20,

      # Spacing
      padding_left: 12,
      padding_right: 12,
      item_spacing: 0,

      # Chevron
      chevron_size: 14,
      chevron_margin: 6
    }
  end

  @doc """
  Get theme by name.

  ## Examples

      iex> Quillex.Utils.SideNavThemes.get(:dark)
      %{background: {35, 37, 47}, ...}
  """
  def get(:dark), do: dark()
  def get(:bare_bones), do: bare_bones()
  def get(:light), do: light()
  # Default to dark theme
  def get(_), do: dark()
end
