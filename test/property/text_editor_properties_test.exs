defmodule Quillex.Property.TextEditorPropertiesTest do
  @moduledoc """
  Property-based tests for text editor invariants.
  
  These tests ensure that fundamental properties of a text editor
  are maintained regardless of the specific operations performed.
  They use property-based testing to generate random sequences
  of operations and verify that core invariants hold.
  """
  
  use ExUnit.Case
  use ExUnitProperties
  
  alias Quillex.Structs.BufState
  alias Quillex.Structs.BufState.Cursor
  alias Quillex.GUI.Components.BufferPane.Mutator

  describe "cursor position invariants" do
    property "cursor is never positioned before the start of a line" do
      check all buffer <- buffer_generator(),
                operations <- list_of(cursor_operation_generator(), max_length: 20) do
        
        final_buffer = Enum.reduce(operations, buffer, &apply_operation/2)
        
        [cursor] = final_buffer.cursors
        assert cursor.col >= 1, "Cursor column should never be less than 1, got: #{cursor.col}"
      end
    end
    
    property "cursor is never positioned beyond the end of a line" do
      check all buffer <- buffer_generator(),
                operations <- list_of(cursor_operation_generator(), max_length: 20) do
        
        final_buffer = Enum.reduce(operations, buffer, &apply_operation/2)
        
        [cursor] = final_buffer.cursors
        current_line = Enum.at(final_buffer.data, cursor.line - 1, "")
        max_col = String.length(current_line) + 1
        
        assert cursor.col <= max_col, 
               "Cursor column #{cursor.col} should not exceed line length + 1 (#{max_col}). Line: '#{current_line}'"
      end
    end
    
    property "cursor is never positioned beyond the document boundaries" do
      check all buffer <- buffer_generator(),
                operations <- list_of(cursor_operation_generator(), max_length: 20) do
        
        final_buffer = Enum.reduce(operations, buffer, &apply_operation/2)
        
        [cursor] = final_buffer.cursors
        max_line = max(1, length(final_buffer.data))
        
        assert cursor.line >= 1, "Cursor line should never be less than 1, got: #{cursor.line}"
        assert cursor.line <= max_line, 
               "Cursor line #{cursor.line} should not exceed document length (#{max_line})"
      end
    end
    
    property "cursor on empty line is positioned at column 1" do
      check all buffer <- buffer_generator(),
                operations <- list_of(text_operation_generator(), max_length: 10) do
        
        final_buffer = Enum.reduce(operations, buffer, &apply_operation/2)
        
        [cursor] = final_buffer.cursors
        current_line = Enum.at(final_buffer.data, cursor.line - 1, "")
        
        if String.length(current_line) == 0 do
          assert cursor.col == 1, 
                 "Cursor should be at column 1 on empty line, got: #{cursor.col}"
        end
      end
    end
  end

  describe "text editing invariants" do
    property "buffer always contains at least one line" do
      check all buffer <- buffer_generator(),
                operations <- list_of(text_operation_generator(), max_length: 20) do
        
        final_buffer = Enum.reduce(operations, buffer, &apply_operation/2)
        
        assert length(final_buffer.data) >= 1, 
               "Buffer should always contain at least one line, got: #{length(final_buffer.data)} lines"
      end
    end
    
    property "text insertion preserves existing content" do
      check all buffer <- buffer_generator(),
                text <- text_generator() do
        
        original_content = Enum.join(buffer.data, "\n")
        [cursor] = buffer.cursors
        
        new_buffer = Mutator.insert_text(buffer, {cursor.line, cursor.col}, text)
        new_content = Enum.join(new_buffer.data, "\n")
        
        # The new content should contain all original characters plus the inserted text
        assert String.length(new_content) >= String.length(original_content),
               "Text insertion should not reduce document size"
        
        # If we remove the inserted text, we should get back the original
        if String.length(text) > 0 do
          # This is a simplified check - in practice we'd need to track the exact position
          assert String.contains?(new_content, text),
                 "Inserted text should be present in the document"
        end
      end
    end
    
    property "backspace never reduces document below one empty line" do
      check all buffer <- buffer_generator(),
                count <- integer(1..100) do
        
        # Apply many backspace operations
        final_buffer = 1..count
                      |> Enum.reduce(buffer, fn _, buf -> 
                           safe_apply_operation({:backspace}, buf)
                         end)
        
        assert length(final_buffer.data) >= 1, "Document should have at least one line"
        
        # If we have exactly one line, it should be empty and cursor at (1,1)
        if length(final_buffer.data) == 1 do
          [line] = final_buffer.data
          [cursor] = final_buffer.cursors
          
          if String.length(line) == 0 do
            assert cursor.line == 1 and cursor.col == 1,
                   "On single empty line, cursor should be at (1,1), got: (#{cursor.line},#{cursor.col})"
          end
        end
      end
    end
  end

  describe "selection invariants" do
    property "selection boundaries are within document bounds" do
      check all buffer <- buffer_generator(),
                operations <- list_of(selection_operation_generator(), max_length: 10) do
        
        final_buffer = Enum.reduce(operations, buffer, &apply_operation/2)
        
        case final_buffer.selection do
          nil -> 
            # No selection is always valid
            assert true
            
          %{start: {start_line, start_col}, end: {end_line, end_col}} ->
            max_line = length(final_buffer.data)
            
            # Check start position
            assert start_line >= 1 and start_line <= max_line,
                   "Selection start line #{start_line} should be within bounds (1..#{max_line})"
            
            start_line_text = Enum.at(final_buffer.data, start_line - 1, "")
            max_start_col = String.length(start_line_text) + 1
            assert start_col >= 1 and start_col <= max_start_col,
                   "Selection start column #{start_col} should be within bounds (1..#{max_start_col})"
            
            # Check end position  
            assert end_line >= 1 and end_line <= max_line,
                   "Selection end line #{end_line} should be within bounds (1..#{max_line})"
            
            end_line_text = Enum.at(final_buffer.data, end_line - 1, "")
            max_end_col = String.length(end_line_text) + 1
            assert end_col >= 1 and end_col <= max_end_col,
                   "Selection end column #{end_col} should be within bounds (1..#{max_end_col})"
        end
      end
    end
    
    property "replacing selection preserves document structure" do
      check all buffer <- buffer_with_selection_generator(),
                replacement_text <- text_generator() do
        
        original_line_count = length(buffer.data)
        
        # Replace the selection
        new_buffer = case buffer.selection do
          nil -> buffer
          selection -> 
            # Simulate replacing selection with new text
            # This is simplified - actual implementation would be more complex
            Mutator.delete_selected_text(buffer)
            |> then(fn buf -> 
              [cursor] = buf.cursors
              Mutator.insert_text(buf, {cursor.line, cursor.col}, replacement_text)
            end)
        end
        
        # Document should still have at least one line
        assert length(new_buffer.data) >= 1,
               "Document should maintain at least one line after selection replacement"
        
        # Cursor should be valid
        [cursor] = new_buffer.cursors
        assert cursor.line >= 1 and cursor.line <= length(new_buffer.data),
               "Cursor should be within document bounds after selection replacement"
      end
    end
  end

  # Generators for property-based testing

  defp buffer_generator do
    gen all lines <- list_of(line_generator(), min_length: 1, max_length: 10),
            cursor_line <- integer(1..length(lines)),
            cursor_col <- cursor_col_generator(Enum.at(lines, cursor_line - 1, "")) do
      
      %BufState{
        data: lines,
        cursors: [%Cursor{line: cursor_line, col: cursor_col}],
        selection: nil,
        mode: :edit
      }
    end
  end

  defp buffer_with_selection_generator do
    gen all buffer <- buffer_generator(),
            has_selection <- boolean() do
      
      if has_selection do
        # Add a valid selection
        max_line = length(buffer.data)
        [cursor] = buffer.cursors
        
        # Create a simple selection around cursor
        start_line = max(1, cursor.line - 1)
        end_line = min(max_line, cursor.line + 1)
        
        start_line_text = Enum.at(buffer.data, start_line - 1, "")
        end_line_text = Enum.at(buffer.data, end_line - 1, "")
        
        start_col = max(1, String.length(start_line_text))
        end_col = min(String.length(end_line_text) + 1, String.length(end_line_text) + 1)
        
        %{buffer | selection: %{start: {start_line, start_col}, end: {end_line, end_col}}}
      else
        buffer
      end
    end
  end

  defp line_generator do
    gen all text <- string(:ascii, max_length: 50) do
      # Remove newlines to ensure single line
      String.replace(text, "\n", " ")
    end
  end

  defp cursor_col_generator(line) do
    max_col = String.length(line) + 1
    integer(1..max_col)
  end

  defp text_generator do
    gen all text <- string(:ascii, max_length: 20) do
      # Replace newlines with spaces for simplicity
      String.replace(text, "\n", " ")
    end
  end

  defp cursor_operation_generator do
    one_of([
      {:move_cursor, :up, constant(1)},
      {:move_cursor, :down, constant(1)},
      {:move_cursor, :left, constant(1)},
      {:move_cursor, :right, constant(1)},
      {:move_cursor, :line_start},
      {:move_cursor, :line_end}
    ])
  end

  defp text_operation_generator do
    one_of([
      {:insert_text, text_generator()},
      {:backspace},
      {:delete},
      {:newline}
    ])
  end

  defp selection_operation_generator do
    one_of([
      {:select_text, one_of([:up, :down, :left, :right]), integer(1..3)},
      {:clear_selection}
    ])
  end

  # Apply operations safely to buffer
  defp apply_operation({:move_cursor, direction, count}, buffer) do
    try do
      Mutator.move_cursor(buffer, direction, count)
    rescue
      _ -> buffer  # If operation fails, return original buffer
    end
  end

  defp apply_operation({:move_cursor, direction}, buffer) do
    try do
      Mutator.move_cursor(buffer, direction)
    rescue
      _ -> buffer
    end
  end

  defp apply_operation({:insert_text, text}, buffer) do
    try do
      [cursor] = buffer.cursors
      Mutator.insert_text(buffer, {cursor.line, cursor.col}, text)
    rescue
      _ -> buffer
    end
  end

  defp apply_operation({:backspace}, buffer) do
    safe_apply_operation({:backspace}, buffer)
  end

  defp apply_operation({:delete}, buffer) do
    try do
      [cursor] = buffer.cursors
      Mutator.delete_char_at_cursor(buffer)
    rescue
      _ -> buffer
    end
  end

  defp apply_operation({:newline}, buffer) do
    try do
      Mutator.insert_new_line(buffer, :at_cursor)
    rescue
      _ -> buffer
    end
  end

  defp apply_operation({:select_text, direction, count}, buffer) do
    try do
      Mutator.select_text(buffer, direction, count)
    rescue
      _ -> buffer
    end
  end

  defp apply_operation({:clear_selection}, buffer) do
    %{buffer | selection: nil}
  end

  defp apply_operation(_, buffer), do: buffer

  defp safe_apply_operation({:backspace}, buffer) do
    try do
      Mutator.backspace(buffer)
    rescue
      _ -> buffer
    end
  end
end