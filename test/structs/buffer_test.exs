defmodule Quillex.Structs.BufStateStructTest do
  use ExUnit.Case, async: true

  alias Quillex.Structs.BufState
  alias Quillex.Structs.BufState.Cursor

  describe "BufState.new/1" do
    test "creates a buffer with default values when given an empty map" do
      buf = BufState.new(%{})

      assert buf.name == "unnamed"
      assert buf.data == [""]
      assert buf.source == nil
      assert buf.read_only? == false
      assert buf.dirty? == false
      assert buf.undo_stack == []
      assert buf.redo_stack == []
      assert buf.undo_max_size == 100
      assert buf.search_query == nil
      assert buf.search_matches == []
      assert buf.search_current_index == 0
    end

    test "assigns a unique UUID to each new buffer" do
      buf1 = BufState.new(%{})
      buf2 = BufState.new(%{})

      assert is_binary(buf1.uuid)
      assert is_binary(buf2.uuid)
      assert buf1.uuid != buf2.uuid
    end

    test "accepts a custom name" do
      buf = BufState.new(%{name: "my_notes.txt"})

      assert buf.name == "my_notes.txt"
    end

    test "accepts custom data as a list of strings" do
      lines = ["line one", "line two", "line three"]
      buf = BufState.new(%{data: lines})

      assert buf.data == lines
    end

    test "raises when data is not a list" do
      assert_raise RuntimeError, fn ->
        BufState.new(%{data: "not a list"})
      end
    end

    test "accepts a custom source" do
      source = %{filepath: "/tmp/test.txt"}
      buf = BufState.new(%{source: source})

      assert buf.source == %{filepath: "/tmp/test.txt"}
    end

    test "creates a default cursor at line 1, column 1" do
      buf = BufState.new(%{})

      assert %Cursor{line: 1, col: 1} = buf.cursor
    end

    test "accepts a custom undo_max_size" do
      buf = BufState.new(%{undo_max_size: 50})

      assert buf.undo_max_size == 50
    end

    test "accepts read_only? flag" do
      buf = BufState.new(%{read_only?: true})

      assert buf.read_only? == true
    end
  end

  describe "BufState struct type" do
    test "is a proper struct" do
      buf = BufState.new(%{})

      assert %BufState{} = buf
    end

    test "has a selection field defaulting to nil" do
      buf = BufState.new(%{})

      assert buf.selection == nil
    end
  end
end
