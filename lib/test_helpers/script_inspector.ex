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
    case ScenicMcp.Probes.script_table() do
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

    # Check for font hashes (long alphanumeric strings)
    font_hash = String.length(text) > 20 and String.match?(text, ~r/^[A-Za-z0-9_-]+$/)

    # Check for script IDs (UUIDs or similar)
    # More specific pattern: must have multiple segments separated by hyphens
    # and look like a UUID or hash (all alphanumeric except hyphens)
    script_id = String.contains?(text, "-") and 
                String.length(text) > 10 and
                String.match?(text, ~r/^[A-Za-z0-9_-]+$/) and
                length(String.split(text, "-")) >= 3

    # Check for underscore-prefixed identifiers (Scenic internal names)
    internal_id = String.starts_with?(text, "_") and String.ends_with?(text, "_")

    # Check for single character strings (likely not user content)
    single_char = String.length(text) == 1

    exact_match or font_hash or script_id or internal_id or single_char
  end

  defp is_gui_element?(_), do: false

  @doc """
  Get all rendered user content as a single concatenated string.
  This filters out GUI elements and only returns actual user content.
  """
  def get_rendered_text_string do
    extract_user_content()
    |> Enum.join("\n")
  end

  # Private helper to extract text from a single script table entry
  defp extract_text_from_script_entry({_id, script_data, _pid}) when is_list(script_data) do
    try do
      # Handle both regular lists and keyword lists
      operations = if Keyword.keyword?(script_data) do
        Enum.map(script_data, fn {key, value} -> {key, value} end)
      else
        script_data
      end

      operations
      |> Enum.flat_map(&extract_text_from_script_operation/1)
    rescue
      error ->
        IO.puts("Error parsing script entry: #{inspect(error)}")
        []
    end
  end

  defp extract_text_from_script_entry({{_id, script_data}, _pid}) when is_list(script_data) do
    try do
      script_data
      |> Enum.flat_map(&extract_text_from_script_operation/1)
    rescue
      error ->
        IO.puts("Error parsing script entry: #{inspect(error)}")
        []
    end
  end

  defp extract_text_from_script_entry({_id, script_data}) when is_list(script_data) do
    try do
      script_data
      |> Enum.flat_map(&extract_text_from_script_operation/1)
    rescue
      error ->
        IO.puts("Error parsing script entry: #{inspect(error)}")
        []
    end
  end

  defp extract_text_from_script_entry(entry) do
    # Don't spam logs - only show occasionally for debugging
    if :rand.uniform(10) == 1 do
      IO.puts("Unexpected script entry format: #{inspect(entry, limit: 5)}")
    end
    []
  end

  # Private helper to extract text from individual script operations
  defp extract_text_from_script_operation(operation) do
    try do
      case operation do
        # Look for draw_text operations - this is where the actual text content is
        {:draw_text, text, _spacing} when is_binary(text) ->
          [text]

        # Handle draw_text without spacing parameter
        {:draw_text, text} when is_binary(text) ->
          [text]

        # Look for other possible text operation formats
        {:text, text} when is_binary(text) ->
          [text]

        # Handle nested operations (scripts can contain other operations)
        {_op, args} when is_list(args) ->
          args |> Enum.flat_map(&extract_text_from_script_operation/1)

        # Handle tuples that might contain text - but be more careful
        tuple when is_tuple(tuple) and tuple_size(tuple) <= 10 ->
          tuple
          |> Tuple.to_list()
          |> Enum.flat_map(&extract_text_from_script_operation/1)

        # Handle lists of operations
        list when is_list(list) and length(list) <= 1000 ->
          list |> Enum.flat_map(&extract_text_from_script_operation/1)

        # If it's a string, include it (though this might be rare)
        text when is_binary(text) ->
          [text]

        # Ignore everything else but log it for debugging
        other ->
          # Only log the first few times to avoid spam
          if :rand.uniform(1000) == 1 do
            IO.puts("Ignoring operation: #{inspect(other, limit: 5)}")
          end
          []
      end
    rescue
      error ->
        IO.puts("Error parsing operation #{inspect(operation, limit: 5)}: #{inspect(error)}")
        []
    end
  end

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
    script_table = ScenicMcp.Probes.script_table()

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
end
