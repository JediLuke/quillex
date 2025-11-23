defmodule QuillEx.Utils.SafeFontLoader do
  @moduledoc """
  Safe font loading utilities for Quillex.
  
  Provides fallback mechanisms to prevent crashes when fonts are not available.
  """
  
  require Logger
  
  @doc """
  Safely loads a font with fallback options.
  
  ## Parameters
  - `preferred_font` - The font you want to use (string or atom)
  - `fallback_fonts` - List of fallback fonts to try (optional)
  - `default_font` - Final fallback font that should always work (optional)
  
  ## Returns
  - `{:ok, font_id}` - Successfully found font
  - `{:error, reason}` - All fonts failed to load
  
  ## Examples
      
      # Try specific font with fallbacks
      SafeFontLoader.load_font_safely("NotoSansSymbols", [:ibm_plex_mono])
      
      # Try font with multiple fallbacks
      SafeFontLoader.load_font_safely(:custom_font, [:ibm_plex_mono, :iosevka])
      
      # Use default system font if all else fails
      SafeFontLoader.load_font_safely("MissingFont")
  """
  def load_font_safely(preferred_font, fallback_fonts \\ [], default_font \\ :ibm_plex_mono) do
    fonts_to_try = [preferred_font | fallback_fonts] ++ [default_font]
    
    fonts_to_try
    |> Enum.uniq() # Remove duplicates
    |> Enum.find_value(fn font ->
      case try_load_font(font) do
        {:ok, font_id} -> 
          if font != preferred_font do
            Logger.info("Font fallback: #{inspect(preferred_font)} not available, using #{inspect(font)}")
          end
          {:ok, font_id}
        {:error, _} -> nil
      end
    end)
    |> case do
      {:ok, font_id} -> {:ok, font_id}
      nil -> {:error, "No fonts available from: #{inspect(fonts_to_try)}"}
    end
  end
  
  @doc """
  Get a safe font for UI components that need symbols/special characters.
  
  Tries to find the best font for displaying symbols, with fallbacks.
  """
  def get_symbol_font() do
    case load_font_safely(:noto_sans_symbols, [:ibm_plex_mono, :iosevka]) do
      {:ok, font} -> font
      {:error, _} -> :ibm_plex_mono # Should always work in Quillex
    end
  end
  
  @doc """
  Get a safe font for UI components that need hieroglyphs.
  """
  def get_hieroglyph_font() do
    case load_font_safely(:noto_sans_egyptian_hieroglyphs, [:ibm_plex_mono, :iosevka]) do
      {:ok, font} -> font
      {:error, _} -> :ibm_plex_mono # Should always work in Quillex
    end
  end
  
  @doc """
  Get a safe monospace font for code/text editing.
  """
  def get_monospace_font() do
    case load_font_safely(:ibm_plex_mono, [:iosevka, :source_code_pro, :fira_code]) do
      {:ok, font} -> font
      {:error, _} -> :ibm_plex_mono # Should always work in Quillex
    end
  end
  
  @doc """
  Check if a font is available without loading it.
  """
  def font_available?(font_id) do
    case try_load_font(font_id) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end
  
  @doc """
  List all available fonts in the current application.
  """
  def list_available_fonts() do
    try do
      QuillEx.Assets.library()
      |> Map.keys()
      |> Enum.filter(&font_available?/1)
    rescue
      _ -> [:ibm_plex_mono] # Fallback list
    end
  end
  
  # Private helper to try loading a single font
  defp try_load_font(font_id) do
    case Scenic.Assets.Static.meta(font_id) do
      {:ok, {Scenic.Assets.Static.Font, _metadata}} -> 
        {:ok, font_id}
      {:ok, {other_type, _}} -> 
        {:error, "#{inspect(font_id)} is #{other_type}, not a font"}
      :error -> 
        {:error, "#{inspect(font_id)} not found"}
      other -> 
        {:error, "Unexpected response: #{inspect(other)}"}
    end
  end
end