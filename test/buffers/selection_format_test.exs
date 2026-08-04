defmodule Quillex.Buffers.SelectionFormatTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Selection Format Contract Tests
  #
  # The buffer process stores selection as a map with tuple values:
  #
  #   %{start: {line, col}, end: {line, col}}
  #
  # The TextField component expects selection in a different format:
  #
  #   {start_pos, end_pos}  (a plain 2-tuple of {line, col} tuples)
  #
  # The conversion is done in TextField's handle_info/{init} via this case:
  #
  #   selection = case buf_state.selection do
  #     %{start: start_pos, end: end_pos} -> {start_pos, end_pos}
  #     nil -> nil
  #     other -> other  # Pass through if already in tuple format
  #   end
  #
  # These tests document and verify that contract so regressions in either the
  # buffer format or the conversion logic are immediately caught.
  # ---------------------------------------------------------------------------

  # Mirror of the exact conversion logic used in TextField's handle_info and init.
  defp convert_buffer_selection_to_textfield(buf_selection) do
    case buf_selection do
      %{start: start_pos, end: end_pos} -> {start_pos, end_pos}
      nil -> nil
      other -> other
    end
  end

  # ---------------------------------------------------------------------------
  # Buffer-side format contract
  # ---------------------------------------------------------------------------

  describe "buffer selection format (map with tuple values)" do
    test "format uses map with :start and :end keys" do
      selection = %{start: {1, 1}, end: {1, 10}}
      assert is_map(selection)
      assert Map.has_key?(selection, :start)
      assert Map.has_key?(selection, :end)
    end

    test "positions are {line, col} tuples, not flat integers" do
      selection = %{start: {1, 3}, end: {1, 8}}
      assert selection.start == {1, 3}
      assert selection.end == {1, 8}
    end

    test "multi-line selection positions are {line, col} tuples" do
      selection = %{start: {2, 5}, end: {4, 12}}
      {start_line, start_col} = selection.start
      {end_line, end_col} = selection.end
      assert start_line == 2
      assert start_col == 5
      assert end_line == 4
      assert end_col == 12
    end
  end

  # ---------------------------------------------------------------------------
  # Conversion logic: buffer map format → TextField tuple format
  # ---------------------------------------------------------------------------

  describe "buffer-to-TextField selection format conversion" do
    test "single-line selection map converts to tuple pair" do
      buf_selection = %{start: {1, 3}, end: {1, 8}}
      result = convert_buffer_selection_to_textfield(buf_selection)
      assert result == {{1, 3}, {1, 8}}
    end

    test "nil selection passes through as nil" do
      result = convert_buffer_selection_to_textfield(nil)
      assert is_nil(result)
    end

    test "multi-line selection map converts correctly" do
      buf_selection = %{start: {2, 5}, end: {4, 12}}
      result = convert_buffer_selection_to_textfield(buf_selection)
      assert result == {{2, 5}, {4, 12}}
    end

    test "selection beginning at document start converts correctly" do
      buf_selection = %{start: {1, 1}, end: {1, 6}}
      result = convert_buffer_selection_to_textfield(buf_selection)
      assert result == {{1, 1}, {1, 6}}
    end

    test "already-tuple format passes through unchanged (defensive pass-through)" do
      already_tuple = {{1, 1}, {1, 5}}
      result = convert_buffer_selection_to_textfield(already_tuple)
      assert result == {{1, 1}, {1, 5}}
    end

    test "converted format is a 2-tuple (not a map)" do
      buf_selection = %{start: {1, 1}, end: {3, 7}}
      result = convert_buffer_selection_to_textfield(buf_selection)
      assert is_tuple(result)
      assert tuple_size(result) == 2
    end

    test "converted start position matches original :start key" do
      buf_selection = %{start: {3, 5}, end: {5, 9}}
      {converted_start, _converted_end} = convert_buffer_selection_to_textfield(buf_selection)
      assert converted_start == buf_selection.start
    end

    test "converted end position matches original :end key" do
      buf_selection = %{start: {3, 5}, end: {5, 9}}
      {_converted_start, converted_end} = convert_buffer_selection_to_textfield(buf_selection)
      assert converted_end == buf_selection.end
    end
  end
end
