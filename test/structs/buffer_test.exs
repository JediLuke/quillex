defmodule QuillEx.Structs.BufferTest do
    use ExUnit.Case
    alias QuillEx.Structs.Buffer

    test "make a new Buffer" do
        new_buf = Buffer.new(%{id: {:buffer, "luke_buf"}})
        assert new_buf == %QuillEx.Structs.Buffer{
            id: {:buffer, "luke_buf"},
            name: "luke_buf",
            data: nil,
            details: nil,
            cursors: [%QuillEx.Structs.Buffer.Cursor{num: 1, line: 1, col: 1}],
            history: [],
            scroll_acc: {0, 0},
            read_only?: false
        }
    end

    test "update the scroll_acc for a Buffer using a scroll delta" do
        new_buf = Buffer.new(%{id: {:buffer, "luke_buf"}})
        assert new_buf.scroll_acc == {0,0}

        %Buffer{} = second_new_buf = new_buf |> Buffer.update(%{scroll: {:delta, {5,5}}})
        assert second_new_buf.scroll_acc == {5,5}

        %Buffer{} = third_new_buf = second_new_buf |> Buffer.update(%{scroll: {:delta, {-5,0}}})
        assert third_new_buf.scroll_acc == {0,5}

        %Buffer{} = fourth_new_buf = third_new_buf |> Buffer.update(%{scroll: {:delta, {100, 100}}})
        assert fourth_new_buf.scroll_acc == {100,105}
    end
    
end
  