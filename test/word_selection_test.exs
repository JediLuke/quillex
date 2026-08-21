defmodule Quillex.WordSelectionTest do
  @moduledoc """
  Ctrl+Shift+Arrow moves a word AND takes the text with it.

  It moved and selected nothing: every other movement key extends the
  selection when Shift is held, and this one was tested for `:ctrl` first, so
  the combination went down the plain word-movement branch and the Shift was
  never looked at.

  Tested here rather than through the keyboard because the spex driver cannot
  send the chord — it passes `[:ctrl, :shift]` and Scenic hands the component
  `[:shift]`. These are the two halves the fix is made of: the key mapping,
  and the buffer action it maps to.
  """
  use ExUnit.Case, async: true

  alias ScenicWidgets.TextField.Reducer, as: TF
  alias ScenicWidgets.TextField.State, as: TFState
  alias Quillex.Structs.BufState
  alias Quillex.Buffer.Process.Reducer, as: BufferReducer

  defp field, do: %TFState{focused: true}

  defp buffer(text, col) do
    %BufState{
      uuid: "t",
      data: [text],
      cursor: %BufState.Cursor{line: 1, col: col},
      selection: nil
    }
  end

  describe "the key mapping" do
    test "Ctrl+Shift+Right asks for a word, with the text" do
      assert TF.input_to_buffer_action(field(), {:key, {:key_right, 1, [:ctrl, :shift]}}) ==
               {:select_text, :next_word}
    end

    test "Ctrl+Shift+Left likewise, backwards" do
      assert TF.input_to_buffer_action(field(), {:key, {:key_left, 1, [:ctrl, :shift]}}) ==
               {:select_text, :prev_word}
    end

    test "and neither modifier alone changed meaning" do
      assert TF.input_to_buffer_action(field(), {:key, {:key_right, 1, [:ctrl]}}) ==
               {:move_cursor, :next_word}

      assert TF.input_to_buffer_action(field(), {:key, {:key_right, 1, [:shift]}}) ==
               {:select_text, :right, 1}

      assert TF.input_to_buffer_action(field(), {:key, {:key_right, 1, []}}) ==
               {:move_cursor, :right, 1}
    end
  end

  describe "the buffer action" do
    test "selecting the next word takes the whole word" do
      out = BufferReducer.process(buffer("haystack more", 1), {:select_text, :next_word})

      assert out.selection == %{start: {1, 1}, end: {1, 10}}
      assert out.cursor.col == 10
    end

    test "selecting the previous word takes it back" do
      out = BufferReducer.process(buffer("haystack more", 10), {:select_text, :prev_word})

      assert out.selection.start == {1, 10}
      assert out.cursor.col < 10
    end

    test "selecting forward then back over the same word leaves nothing selected" do
      # Contracting a selection onto its own start is emptiness, not a
      # zero-width selection nobody can see.
      out =
        buffer("haystack more", 1)
        |> BufferReducer.process({:select_text, :next_word})
        |> BufferReducer.process({:select_text, :prev_word})

      assert out.selection == nil
    end
  end
end
