defmodule Quillex.Utils.SideNavThemes do
  @moduledoc """
  Theme definitions for SideNav component in Quillex.

  Provides both a bare-bones default theme and a polished dark theme
  based on the merlinex app styling conventions.
  """

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
      background: {35, 37, 47},              # Dark blue-gray (list_bg)
      text: {220, 220, 230},                 # Light gray text
      active_bg: {60, 80, 120},              # Blue-tinted active background
      active_bar: {100, 160, 220},           # Bright blue accent bar
      hover_bg: {55, 58, 70},                # Slightly lighter hover
      chevron: {140, 140, 150},              # Medium gray chevrons
      focus_ring: {100, 160, 220},           # Blue focus ring
      border: {50, 52, 62},                  # Subtle border

      # Dimensions
      item_height: 26,                       # Compact but readable
      indent: 14,                            # Indentation per level
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
      hover_bg: {55, 55, 60},
      chevron: {150, 150, 150},
      focus_ring: :cyan,
      border: {60, 60, 65},

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
      hover_bg: {240, 240, 245},
      chevron: {80, 80, 80},
      focus_ring: {0, 112, 214},
      border: {220, 220, 225},

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
  def get(_), do: dark()  # Default to dark theme
end
