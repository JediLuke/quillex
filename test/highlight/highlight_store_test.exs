defmodule Quillex.RadixCache.HighlightStoreTest do
  use ExUnit.Case, async: false

  alias Quillex.RadixCache.HighlightStore

  test "switching to a plain document cancels pending highlighted work" do
    state = %{
      buffer_id: nil,
      lexer: nil,
      lines: [],
      hash: nil,
      cache: %{},
      task: nil,
      debounce: nil,
      waiters: []
    }

    highlighted = %{uuid: "source", data: ["def hello, do: :ok"], source: %{filepath: "a.ex"}}
    plain = %{uuid: "plain", data: ["ordinary text"], source: %{filepath: "notes.txt"}}

    assert {:noreply, pending} =
             HighlightStore.handle_info(
               {{Scenic.PubSub, :data}, {:radix_pane_main, highlighted, 0}},
               state
             )

    assert is_reference(pending.debounce)

    assert {:noreply, settled} =
             HighlightStore.handle_info(
               {{Scenic.PubSub, :data}, {:radix_pane_main, plain, 1}},
               pending
             )

    assert settled.buffer_id == "plain"
    assert settled.lexer == nil
    assert settled.debounce == nil
    assert settled.task == nil

    assert_receive {:lex, stale_ref}, 200
    assert {:noreply, unchanged} = HighlightStore.handle_info({:lex, stale_ref}, settled)
    assert unchanged == settled
  end
end
