defmodule Quillex.TestHelpers.ScriptInspector do
  @moduledoc """
  Helper functions for inspecting the Scenic script table to extract rendered content.

  These functions provide true end-to-end testing by examining what actually gets
  rendered to the screen, rather than just checking internal buffer state.
  """

  @doc """
  Extract all text content from the script table that is currently being rendered.
  Returns a list of text strings found in the rendering scripts, sorted by visual position.
  """
  def extract_rendered_text do
    case get_script_table() do
      script_entries when is_list(script_entries) ->
        # Extract text with position information
        text_with_positions = script_entries
        |> Enum.flat_map(&extract_text_with_position_from_entry/1)

        # Sort by Y position (vertical), then X position (horizontal)
        text_with_positions
        |> Enum.sort_by(fn {_text, {x, y}} -> {y, x} end)
        |> Enum.map(fn {text, _pos} -> text end)
        |> Enum.uniq()

      _ -> []
    end
  end

  # Helper function to get script table using the new ScenicMcp.Tools API
  defp get_script_table do
    case ScenicMcp.Tools.viewport_state() do
      {:ok, %{script_table: script_table}} when script_table != nil ->
        :ets.tab2list(script_table)
      _ ->
        []
    end
  end

  @doc """
  Check if any rendered user content contains the specified string.
  This filters out GUI elements and only looks at actual user content.
  """
  def rendered_text_contains?(text) when is_binary(text) do
    extract_user_content()
    |> Enum.any?(fn rendered_text ->
      String.contains?(rendered_text, text)
    end)
  end

  @doc """
  Check if the rendered output appears to be empty (no user content).
  This filters out GUI elements and only looks for actual user-typed content.
  """
  def rendered_text_empty? do
    user_content = extract_user_content()

    user_content == [] or
    Enum.all?(user_content, fn text ->
      String.trim(text) == ""
    end)
  end

  @doc """
  Extract only user-typed content, filtering out GUI elements.
  """
  def extract_user_content do
    extract_rendered_text()
    |> Enum.reject(&is_gui_element?/1)
  end

  # Filter out common GUI elements that aren't user content
  defp is_gui_element?(text) when is_binary(text) do
    gui_patterns = [
      # Button/menu text
      "Help", "About", "Options", "Buffers",
      # Common symbols
      "[+]", "{ }", "[=]", "(o)", "<*>", ">_", "Y",
      # Single characters that are likely UI elements
      "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
      # Scenic script identifiers
      "_main_", "_root_"
    ]

    # Check for exact matches with GUI patterns
    exact_match = text in gui_patterns

    # Check for font hashes (long alphanumeric strings that look like hashes)
    # Font hashes typically have mixed case, numbers, and underscores/hyphens
    font_hash = String.length(text) > 30 and 
                String.match?(text, ~r/^[A-Za-z0-9_-]+$/) and
                (String.contains?(text, "_") or String.contains?(text, "-") or
                 String.match?(text, ~r/[0-9]/))  # Must have numbers or special chars to be a hash

    # Check for script IDs (UUIDs or similar)
    # More specific pattern: must have multiple segments separated by hyphens
    # and look like a UUID or hash (all alphanumeric except hyphens)
    script_id = String.contains?(text, "-") and 
                String.length(text) > 10 and
                String.match?(text, ~r/^[A-Za-z0-9_-]+$/) and
                length(String.split(text, "-")) >= 3

    # Check for underscore-prefixed identifiers (Scenic internal names)
    internal_id = String.starts_with?(text, "_") and String.ends_with?(text, "_")

    # Don't filter out all single characters - only those in gui_patterns
    # This allows legitimate single-character user input like 'A', 'B', etc.
    
    exact_match or font_hash or script_id or internal_id
  end

  defp is_gui_element?(_), do: false


  # These functions are no longer used - we now use position-based extraction
  # Keeping them commented for reference if needed later
  
  # # Private helper to extract text from a single script table entry
  # defp extract_text_from_script_entry({_id, script_data, _pid}) when is_list(script_data) do
  #   ...removed for brevity...
  # end

  # Private helper to extract text with position from a single script table entry
  defp extract_text_with_position_from_entry({_id, script_data, _pid}) when is_list(script_data) do
    extract_text_with_position_from_operations(script_data)
  end

  defp extract_text_with_position_from_entry({{_id, script_data}, _pid}) when is_list(script_data) do
    extract_text_with_position_from_operations(script_data)
  end

  defp extract_text_with_position_from_entry({_id, script_data}) when is_list(script_data) do
    extract_text_with_position_from_operations(script_data)
  end

  defp extract_text_with_position_from_entry(_entry) do
    []
  end

  # Extract text with position from a list of operations
  defp extract_text_with_position_from_operations(operations) do
    # Track current transform position as we process operations
    {texts, _} = operations
    |> Enum.reduce({[], {0, 0}}, fn op, {acc, current_pos} ->
      case op do
        # Update position when we see a translate operation
        {:translate, {x, y}} ->
          {acc, {x, y}}
          
        # Extract text at current position
        {:draw_text, text, _spacing} when is_binary(text) ->
          {[{text, current_pos} | acc], current_pos}
          
        {:draw_text, text} when is_binary(text) ->
          {[{text, current_pos} | acc], current_pos}
          
        {:text, text} when is_binary(text) ->
          {[{text, current_pos} | acc], current_pos}
          
        # Skip other operations
        _ ->
          {acc, current_pos}
      end
    end)
    
    Enum.reverse(texts)
  end

  @doc """
  Debug function to inspect the raw script table structure.
  Useful for understanding what's in the script table during development.
  """
  def debug_script_table do
    script_table = get_script_table()

    IO.puts("\n=== SCRIPT TABLE DEBUG ===")
    IO.puts("Number of entries: #{length(script_table)}")

    script_table
    |> Enum.with_index()
    |> Enum.each(fn {entry, index} ->
      case entry do
        {id, script, _pid} ->
          IO.puts("\n--- Entry #{index} (ID: #{inspect(id)}) ---")
          IO.inspect(script, limit: 50, pretty: true)

        {{id, script}, _pid} ->
          IO.puts("\n--- Entry #{index} (ID: #{inspect(id)}) ---")
          IO.inspect(script, limit: 50, pretty: true)

        {id, script} ->
          IO.puts("\n--- Entry #{index} (ID: #{inspect(id)}) ---")
          IO.inspect(script, limit: 50, pretty: true)

        other ->
          IO.puts("\n--- Entry #{index} (Unknown format) ---")
          IO.inspect(other, limit: 10, pretty: true)
      end
    end)

    IO.puts("\n=== EXTRACTED TEXT ===")
    extracted_text = extract_rendered_text()
    IO.inspect(extracted_text, label: "All rendered text")

    user_content = extract_user_content()
    IO.inspect(user_content, label: "User content (filtered)")

    gui_elements = extracted_text -- user_content
    IO.inspect(gui_elements, label: "GUI elements (filtered out)")

    script_table
  end

  @doc """
  Get all rendered text as a single string, joining lines with newlines.
  This maintains the visual layout of the text as it appears on screen.
  Filters out GUI elements and line numbers.
  """
  def get_rendered_text_string do
    extract_user_content()
    |> Enum.join("\n")
  end

  @doc """
  Get all rendered text as a single string, joining lines with spaces.
  Useful when you want to search for text that might wrap across lines.
  Filters out GUI elements and line numbers.
  """
  def get_rendered_text_flat do
    extract_user_content()
    |> Enum.join(" ")
  end
end
