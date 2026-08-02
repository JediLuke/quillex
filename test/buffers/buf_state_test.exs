defmodule Quillex.Structs.BufStateTest do
  use ExUnit.Case, async: true
  alias Quillex.Structs.BufState

  test "BufState.new creates a valid buffer with defaults" do
    buf = BufState.new(%{name: "test-buf"})
    assert %BufState{} = buf
    assert buf.name == "test-buf"
    assert buf.data == [""]
    assert buf.dirty? == false
    assert buf.read_only? == false
    assert is_binary(buf.uuid)
    assert %BufState.Cursor{} = buf.cursor
    assert buf.undo_stack == []
    assert buf.redo_stack == []
    assert buf.search_query == nil
  end

  test "BufState.new with custom data" do
    buf = BufState.new(%{name: "data-buf", data: ["line one", "line two"]})
    assert buf.data == ["line one", "line two"]
    assert buf.name == "data-buf"
  end

  test "BufState.new uses 'unnamed' as default name" do
    buf = BufState.new(%{})
    assert buf.name == "unnamed"
  end
end
