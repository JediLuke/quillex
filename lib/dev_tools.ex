defmodule Quillex.DevTools do
  @moduledoc """
  Quillex-specific developer tools that extend Scenic.DevTools.
  
  This module provides text editor-specific functionality on top of
  the generic Scenic developer tools.
  
  ## Usage
  
      iex> import Quillex.DevTools
      iex> import Scenic.DevTools      # Also import the base tools
      
      # Use Scenic's primary inspection
      iex> inspect_viewport()           # Full viewport inspection
      
      # Quillex-specific tools
      iex> buffers()                   # List all text buffers
      iex> buffer(1)                   # Show buffer content
      iex> cursor_info()               # Show cursor position & context
      iex> selection_info()            # Show current selection
      iex> buffer_stats()              # Detailed buffer statistics
      iex> syntax_info()               # Language/syntax detection
  """
  
  alias Scenic.ViewPort
  
  @doc """
  List all text buffers with content preview.
  
  This is a text-editor specific function that shows all
  buffers currently loaded in the editor.
  """
  def buffers(viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      entries = :ets.tab2list(viewport.semantic_table)
      
      buffers = for {_graph_key, data} <- entries,
                    id <- Map.get(data.by_type, :text_buffer, []),
                    elem = Map.get(data.elements, id),
                    do: elem
      
      if buffers == [] do
        IO.puts("No text buffers found")
        IO.puts("\nMake sure your editor has semantic annotations:")
        IO.puts("  semantic: Semantic.text_buffer(buffer_id: buf.uuid)")
      else
        IO.puts("\n📝 Text Buffers:")
        Enum.with_index(buffers, 1)
        |> Enum.each(fn {buffer, idx} ->
          content = buffer.content || ""
          preview = content
            |> String.split("\n", parts: 2)
            |> List.first()
            |> String.slice(0, 60)
          
          preview = if String.length(content) > 60, do: preview <> "...", else: preview
          
          buffer_id = buffer.semantic.buffer_id
          short_id = if is_binary(buffer_id) && String.length(buffer_id) > 8,
            do: String.slice(buffer_id, 0, 8) <> "...",
            else: to_string(buffer_id)
            
          # Show file path if available
          file_info = if buffer.semantic[:file_path] do
            " (#{Path.basename(buffer.semantic.file_path)})"
          else
            ""
          end
          
          IO.puts("[#{idx}] Buffer #{short_id}#{file_info}: \"#{preview}\"")
        end)
        
        IO.puts("\nTip: Use buffer(n) to see full content")
      end
      :ok
    end
  end
  
  @doc """
  Show content of a specific buffer.
  
  ## Examples
  
      iex> buffer(1)           # By index from buffers() list
      iex> buffer("uuid-123")  # By buffer ID
      iex> buffer("main.ex")   # By filename (if unique)
  """
  def buffer(id, viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      entries = :ets.tab2list(viewport.semantic_table)
      
      # Find buffer by ID, index, or filename
      buffer = find_buffer_by_id(entries, id)
      
      case buffer do
        nil ->
          IO.puts("Buffer not found: #{inspect(id)}")
          IO.puts("\nTip: Use buffers() to see available buffers")
          
        elem ->
          semantic = elem.semantic
          content = elem.content || "(empty)"
          
          IO.puts("\n📝 Buffer Details:")
          IO.puts("ID: #{semantic.buffer_id}")
          if semantic[:file_path], do: IO.puts("File: #{semantic.file_path}")
          IO.puts("Editable: #{semantic[:editable] || true}")
          if semantic[:modified], do: IO.puts("Modified: yes")
          
          # Text stats
          lines = String.split(content, "\n")
          words = length(String.split(content, ~r/\\s+/, trim: true))
          IO.puts("\nStats: #{length(lines)} lines, #{words} words, #{String.length(content)} chars")
          
          # Show cursor if available
          if semantic[:cursor_position] do
            {line, col} = semantic.cursor_position
            IO.puts("Cursor: Line #{line}, Column #{col}")
          end
          
          IO.puts("\n--- Content ---")
          IO.puts(content)
          IO.puts("--- End ---")
      end
      :ok
    end
  end
  
  @doc """
  Show cursor position and surrounding context.
  
  Finds text buffers with cursor information and shows
  the cursor position with surrounding text context.
  """
  def cursor_info(viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      entries = :ets.tab2list(viewport.semantic_table)
      
      # Find buffers with cursor info
      buffers_with_cursor = for {_graph_key, data} <- entries,
                                id <- Map.get(data.by_type, :text_buffer, []),
                                elem = Map.get(data.elements, id),
                                elem.semantic[:cursor_position],
                                do: elem
      
      if buffers_with_cursor == [] do
        IO.puts("No cursor position information found")
        IO.puts("\nℹ️  Add cursor info to semantic data:")
        IO.puts("  semantic: %{cursor_position: {line, col}, ...}")
      else
        IO.puts("\n🎯 Cursor Information:")
        
        Enum.each(buffers_with_cursor, fn buffer ->
          {line, col} = buffer.semantic.cursor_position
          buffer_id = short_id(buffer.semantic.buffer_id)
          
          IO.puts("\nBuffer #{buffer_id}:")
          IO.puts("  Position: Line #{line}, Column #{col}")
          
          # Show context if we have content
          if buffer.content do
            show_cursor_context(buffer.content, line, col)
          end
        end)
      end
      :ok
    end
  end
  
  @doc """
  Show current text selection information.
  
  Displays selected text, selection range, and stats.
  """
  def selection_info(viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      entries = :ets.tab2list(viewport.semantic_table)
      
      # Find buffers with selection
      buffers_with_selection = for {_graph_key, data} <- entries,
                                   id <- Map.get(data.by_type, :text_buffer, []),
                                   elem = Map.get(data.elements, id),
                                   elem.semantic[:selection],
                                   do: elem
      
      if buffers_with_selection == [] do
        IO.puts("No active selections")
      else
        IO.puts("\n✂️  Selection Information:")
        
        Enum.each(buffers_with_selection, fn buffer ->
          selection = buffer.semantic.selection
          buffer_id = short_id(buffer.semantic.buffer_id)
          
          IO.puts("\nBuffer #{buffer_id}:")
          IO.puts("  Range: #{inspect(selection)}")
          
          # Extract and show selected text if possible
          if buffer.content && is_map(selection) do
            selected_text = extract_selection(buffer.content, selection)
            if selected_text do
              lines = length(String.split(selected_text, "\n"))
              chars = String.length(selected_text)
              
              IO.puts("  Size: #{lines} lines, #{chars} characters")
              IO.puts("\n  Selected text:")
              IO.puts("  #{String.replace(selected_text, "\n", "\n  ")}")
            end
          end
        end)
      end
      :ok
    end
  end
  
  @doc """
  Show detailed buffer statistics.
  
  Provides in-depth analysis of text content including
  word frequency, line lengths, and code metrics.
  """
  def buffer_stats(viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      entries = :ets.tab2list(viewport.semantic_table)
      
      buffers = for {_graph_key, data} <- entries,
                    id <- Map.get(data.by_type, :text_buffer, []),
                    elem = Map.get(data.elements, id),
                    do: elem
      
      if buffers == [] do
        IO.puts("No text buffers found")
      else
        IO.puts("\n📊 Buffer Statistics:")
        
        Enum.each(buffers, fn buffer ->
          content = buffer.content || ""
          buffer_id = short_id(buffer.semantic.buffer_id)
          
          IO.puts("\n━━━ Buffer #{buffer_id} ━━━")
          
          # Basic stats
          lines = String.split(content, "\n")
          line_count = length(lines)
          char_count = String.length(content)
          word_count = length(String.split(content, ~r/\s+/, trim: true))
          
          IO.puts("Basic:")
          IO.puts("  Lines: #{line_count}")
          IO.puts("  Characters: #{char_count}")
          IO.puts("  Words: #{word_count}")
          
          if line_count > 0 do
            # Line length stats
            line_lengths = Enum.map(lines, &String.length/1)
            avg_length = round(Enum.sum(line_lengths) / line_count)
            max_length = Enum.max(line_lengths)
            
            IO.puts("\nLine Lengths:")
            IO.puts("  Average: #{avg_length} chars")
            IO.puts("  Maximum: #{max_length} chars")
            IO.puts("  Empty lines: #{Enum.count(lines, &(&1 == ""))}")
            
            # Code-specific stats
            if seems_like_code?(content) do
              IO.puts("\nCode Metrics:")
              IO.puts("  Functions: #{count_pattern(content, ~r/\b(def|defp|fn)\s+/)}")
              IO.puts("  Comments: #{count_pattern(content, ~r/^\s*#/m)}")
              IO.puts("  Indented lines: #{Enum.count(lines, &String.starts_with?(&1, " "))}")
            end
          end
        end)
      end
      :ok
    end
  end
  
  @doc """
  Detect and show syntax/language information.
  
  Analyzes buffer content to determine the programming
  language or file type.
  """
  def syntax_info(viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      entries = :ets.tab2list(viewport.semantic_table)
      
      buffers = for {_graph_key, data} <- entries,
                    id <- Map.get(data.by_type, :text_buffer, []),
                    elem = Map.get(data.elements, id),
                    elem.content && elem.content != "",
                    do: elem
      
      if buffers == [] do
        IO.puts("No buffers with content found")
      else
        IO.puts("\n🔍 Syntax Detection:")
        
        Enum.each(buffers, fn buffer ->
          buffer_id = short_id(buffer.semantic.buffer_id)
          language = detect_language(buffer.content)
          file_path = buffer.semantic[:file_path]
          
          IO.puts("\nBuffer #{buffer_id}:")
          if file_path, do: IO.puts("  File: #{file_path}")
          IO.puts("  Detected: #{language}")
          
          # Show language-specific info
          case language do
            "Elixir" ->
              modules = Regex.scan(~r/defmodule\s+(\S+)/, buffer.content)
              if modules != [] do
                module_names = Enum.map(modules, fn [_, name] -> name end)
                IO.puts("  Modules: #{Enum.join(module_names, ", ")}")
              end
              
            "Markdown" ->
              headers = Regex.scan(~r/^#+\s+(.+)$/m, buffer.content)
              if length(headers) > 0 do
                IO.puts("  Headers: #{length(headers)}")
              end
              
            _ -> :ok
          end
        end)
      end
      :ok
    end
  end
  
  # ============================================================================
  # Private Helpers
  # ============================================================================
  
  defp get_viewport(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> {:error, "ViewPort #{inspect(name)} not found"}
      pid -> ViewPort.info(pid)
    end
  end
  
  defp short_id(id) when is_binary(id) and byte_size(id) > 8 do
    String.slice(id, 0, 8) <> "..."
  end
  defp short_id(id), do: to_string(id)
  
  defp find_buffer_by_id(entries, id) when is_integer(id) do
    # Find by index
    buffers = for {_graph_key, data} <- entries,
                  buffer_id <- Map.get(data.by_type, :text_buffer, []),
                  elem = Map.get(data.elements, buffer_id),
                  do: elem
    
    Enum.at(buffers, id - 1)
  end
  
  defp find_buffer_by_id(entries, id) when is_binary(id) do
    # Try to find by buffer ID first
    result = Enum.find_value(entries, fn {_graph_key, data} ->
      data.elements
      |> Map.values()
      |> Enum.find(fn elem ->
        elem.semantic.type == :text_buffer && 
        to_string(elem.semantic.buffer_id) == id
      end)
    end)
    
    # If not found by ID, try by filename
    result || Enum.find_value(entries, fn {_graph_key, data} ->
      data.elements
      |> Map.values()
      |> Enum.find(fn elem ->
        elem.semantic.type == :text_buffer && 
        elem.semantic[:file_path] && 
        (Path.basename(elem.semantic.file_path) == id ||
         elem.semantic.file_path == id)
      end)
    end)
  end
  
  defp find_buffer_by_id(entries, id) do
    # Fallback for other types
    find_buffer_by_id(entries, to_string(id))
  end
  
  defp show_cursor_context(content, line, col) do
    lines = String.split(content, "\n")
    
    # Get the line with cursor (1-indexed)
    if line > 0 and line <= length(lines) do
      current_line = Enum.at(lines, line - 1)
      
      # Show line with cursor indicator
      IO.puts("\n  Context:")
      
      # Previous line if exists
      if line > 1 do
        prev_line = Enum.at(lines, line - 2)
        IO.puts("  #{line - 1}: #{prev_line}")
      end
      
      # Current line with cursor
      IO.puts("  #{line}: #{current_line}")
      
      # Cursor indicator
      cursor_padding = String.duplicate(" ", col - 1 + String.length("  #{line}: "))
      IO.puts("  #{cursor_padding}^")
      
      # Next line if exists
      if line < length(lines) do
        next_line = Enum.at(lines, line)
        IO.puts("  #{line + 1}: #{next_line}")
      end
    end
  end
  
  defp extract_selection(content, %{start: start_pos, end: end_pos}) do
    # Simple extraction - would need proper implementation
    # based on your selection format
    try do
      String.slice(content, start_pos..end_pos)
    rescue
      _ -> nil
    end
  end
  
  defp extract_selection(_, _), do: nil
  
  defp seems_like_code?(content) do
    # Simple heuristics
    patterns = [
      ~r/\b(def|defp|defmodule|if|else|end)\b/,     # Elixir
      ~r/\b(function|const|let|var|return)\b/,       # JavaScript
      ~r/\b(class|def|import|from|return)\b/,        # Python
      ~r/[{}();]/,                                    # Common code syntax
      ~r/^\s{2,}/m                                    # Indentation
    ]
    
    Enum.any?(patterns, &Regex.match?(&1, content))
  end
  
  defp count_pattern(content, pattern) do
    pattern
    |> Regex.scan(content)
    |> length()
  end
  
  defp detect_language(content) do
    cond do
      # Elixir
      String.contains?(content, "defmodule") || 
      Regex.match?(~r/\b(def|defp)\s+\w+/, content) ->
        "Elixir"
        
      # JavaScript/TypeScript
      Regex.match?(~r/\b(function|const|let|var)\s+\w+\s*=/, content) ||
      Regex.match?(~r/\b(import|export)\s+.*from/, content) ->
        "JavaScript/TypeScript"
        
      # Python
      Regex.match?(~r/^\s*def\s+\w+\(/m, content) ||
      Regex.match?(~r/^\s*class\s+\w+/m, content) ->
        "Python"
        
      # Ruby
      Regex.match?(~r/^\s*class\s+\w+\s*</m, content) ||
      Regex.match?(~r/^\s*def\s+\w+/m, content) && !String.contains?(content, "defmodule") ->
        "Ruby"
        
      # Markdown
      Regex.match?(~r/^#\s+|^##\s+|^###\s+/m, content) ||
      Regex.match?(~r/^\*\s+|\-\s+|\d+\.\s+/m, content) ->
        "Markdown"
        
      # HTML/XML
      Regex.match?(~r/<\w+.*>.*<\/\w+>/s, content) ->
        "HTML/XML"
        
      # JSON
      Regex.match?(~r/^\s*\{[\s\S]*\}\s*$/m, content) && 
      String.contains?(content, ":") ->
        "JSON"
        
      true ->
        "Plain text"
    end
  end
end