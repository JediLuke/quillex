defmodule QuillEx.Utils.SafeFontLoaderTest do
  use ExUnit.Case, async: true
  alias QuillEx.Utils.SafeFontLoader
  
  describe "load_font_safely/3" do
    test "returns preferred font when available" do
      assert {:ok, :ibm_plex_mono} = SafeFontLoader.load_font_safely(:ibm_plex_mono)
    end
    
    test "falls back to fallback font when preferred is not available" do
      assert {:ok, :ibm_plex_mono} = SafeFontLoader.load_font_safely("NonExistentFont", [:ibm_plex_mono])
    end
    
    test "tries multiple fallbacks" do
      assert {:ok, :ibm_plex_mono} = SafeFontLoader.load_font_safely("NonExistentFont", ["AlsoNonExistent", :ibm_plex_mono])
    end
    
    test "uses default font when all else fails" do
      assert {:ok, :ibm_plex_mono} = SafeFontLoader.load_font_safely("NonExistentFont", ["AlsoNonExistent"], :ibm_plex_mono)
    end
    
    test "returns error when no fonts are available" do
      assert {:error, _reason} = SafeFontLoader.load_font_safely("NonExistentFont", ["AlsoNonExistent"], "AlsoNotThere")
    end
  end
  
  describe "font_available?/1" do
    test "returns true for available fonts" do
      assert SafeFontLoader.font_available?(:ibm_plex_mono)
      assert SafeFontLoader.font_available?(:iosevka)
    end
    
    test "returns false for unavailable fonts" do
      refute SafeFontLoader.font_available?("NonExistentFont")
      refute SafeFontLoader.font_available?(:non_existent_font)
    end
  end
  
  describe "helper functions" do
    test "get_symbol_font/0 returns a valid font" do
      font = SafeFontLoader.get_symbol_font()
      assert SafeFontLoader.font_available?(font)
    end
    
    test "get_hieroglyph_font/0 returns a valid font" do
      font = SafeFontLoader.get_hieroglyph_font()
      assert SafeFontLoader.font_available?(font)
    end
    
    test "get_monospace_font/0 returns a valid font" do
      font = SafeFontLoader.get_monospace_font()
      assert SafeFontLoader.font_available?(font)
    end
  end
  
  describe "list_available_fonts/0" do
    test "returns a list of available fonts" do
      fonts = SafeFontLoader.list_available_fonts()
      assert is_list(fonts)
      # Should at least include these fonts available in Quillex
      assert :ibm_plex_mono in fonts
      assert :iosevka in fonts
    end
  end
end