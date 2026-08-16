defmodule Quillex.Buffer.BufferReorderTest do
  use ExUnit.Case, async: true

  alias Quillex.Buffer.{BufferManager, Ref}

  test "reorder_state applies a complete UUID permutation and preserves active buffer" do
    a = %Ref{uuid: "a", name: "a"}
    b = %Ref{uuid: "b", name: "b"}
    c = %Ref{uuid: "c", name: "c"}

    assert {:ok, reordered} =
             BufferManager.reorder_state(%{buffers: [a, b, c], active_buf: b}, ["c", "a", "b"])

    assert Enum.map(reordered.buffers, & &1.uuid) == ["c", "a", "b"]
    assert reordered.active_buf == b
  end

  test "reorder_state rejects missing, duplicate, or foreign UUIDs" do
    a = %Ref{uuid: "a", name: "a"}
    b = %Ref{uuid: "b", name: "b"}
    state = %{buffers: [a, b], active_buf: a}

    assert :invalid_order = BufferManager.reorder_state(state, ["a"])
    assert :invalid_order = BufferManager.reorder_state(state, ["a", "a"])
    assert :invalid_order = BufferManager.reorder_state(state, ["a", "foreign"])
  end
end
