defmodule Quillex.SideNav.RenameEditingTest do
  @moduledoc """
  The file navigator's inline rename box is a single-line text input, and
  these pin the caret arithmetic that makes it one.

  It used to be a picture of one. Starting a rename seeded `rename_value`
  with the file's basename and set `rename_replace_on_input: true`, so the
  first character typed threw the name away — the box looked pre-filled and
  behaved blank. There was no caret position anywhere in the state either:
  the renderer drew `rename_value <> "|"`, typing appended, and Left/Right
  fell through to the tree's own arrow-key navigation, moving the selection
  underneath the open rename box.

  `ScenicWidgets.SideNav.Reducer`'s rename primitives are the seam worth
  testing: pure `%State{} -> %State{}`, no viewport, no component process.
  They live in scenic-widget-contrib, whose own suite cannot build here
  (scenic_driver_local wants cairo headers), so its tests live in quillex —
  the same arrangement as `test/text_field/`.
  """

  use ExUnit.Case, async: true

  alias ScenicWidgets.SideNav.Reducer
  alias ScenicWidgets.SideNav.State

  # Only the rename fields matter to these functions; the rest of a SideNav
  # state (tree, scroll, frame, theme) is untouched by every one of them.
  defp renaming(value, caret) do
    %State{renaming_id: "/tmp/project/#{value}", rename_value: value, rename_caret: caret}
  end

  defp caret(state), do: state.rename_caret

  describe "starting a rename" do
    test "seeds the existing basename with the caret at the end" do
      state = Reducer.start_rename(%State{}, "/tmp/project/notes.txt")

      assert state.renaming_id == "/tmp/project/notes.txt"
      assert state.rename_value == "notes.txt"
      assert state.rename_caret == String.length("notes.txt")
    end

    test "the seeded name survives the first keystroke" do
      # The reported bug, in one assertion: typing used to discard the name.
      state =
        %State{}
        |> Reducer.start_rename("/tmp/project/notes.txt")
        |> Reducer.rename_insert("2")

      assert state.rename_value == "notes.txt2"
    end

    test "a directory keeps only its basename, not its path" do
      state = Reducer.start_rename(%State{}, "/tmp/project/nested/dir")
      assert state.rename_value == "dir"
    end
  end

  describe "caret movement" do
    test "Left and Right walk the name one grapheme at a time" do
      state = renaming("notes.txt", 9)

      assert state |> Reducer.rename_caret_left() |> caret() == 8

      assert state
             |> Reducer.rename_caret_left()
             |> Reducer.rename_caret_left()
             |> caret() == 7

      assert renaming("notes.txt", 3) |> Reducer.rename_caret_right() |> caret() == 4
    end

    test "the caret stops at both ends instead of running off them" do
      assert renaming("notes.txt", 0) |> Reducer.rename_caret_left() |> caret() == 0
      assert renaming("notes.txt", 9) |> Reducer.rename_caret_right() |> caret() == 9
    end

    test "Home and End jump to the ends" do
      assert renaming("notes.txt", 4) |> Reducer.rename_caret_home() |> caret() == 0
      assert renaming("notes.txt", 4) |> Reducer.rename_caret_end() |> caret() == 9
    end

    test "moving the caret never touches the name" do
      state = renaming("notes.txt", 4)

      for moved <- [
            Reducer.rename_caret_left(state),
            Reducer.rename_caret_right(state),
            Reducer.rename_caret_home(state),
            Reducer.rename_caret_end(state)
          ] do
        assert moved.rename_value == "notes.txt"
      end
    end
  end

  describe "typing" do
    test "inserts at the caret, not at the end" do
      # Left-arrow back off the extension, then type: the user's actual path.
      state =
        %State{}
        |> Reducer.start_rename("/tmp/project/notes.txt")
        |> Reducer.rename_caret_left()
        |> Reducer.rename_caret_left()
        |> Reducer.rename_caret_left()
        |> Reducer.rename_caret_left()
        |> Reducer.rename_insert("-v2")

      assert state.rename_value == "notes-v2.txt"
      assert state.rename_caret == 8
    end

    test "inserting at the start keeps the whole name after it" do
      state = renaming("notes.txt", 0) |> Reducer.rename_insert("my-")

      assert state.rename_value == "my-notes.txt"
      assert state.rename_caret == 3
    end

    test "counts graphemes, not bytes" do
      state = renaming("résumé.txt", 6) |> Reducer.rename_insert("!")

      assert state.rename_value == "résumé!.txt"
      assert state.rename_caret == 7
    end
  end

  describe "deleting" do
    test "Backspace removes the grapheme before the caret" do
      state = renaming("notes.txt", 5) |> Reducer.rename_backspace()

      assert state.rename_value == "note.txt"
      assert state.rename_caret == 4
    end

    test "Backspace at the start of the name is a no-op" do
      state = renaming("notes.txt", 0)
      assert Reducer.rename_backspace(state) == state
    end

    test "Delete removes the grapheme at the caret and leaves the caret put" do
      state = renaming("notes.txt", 4) |> Reducer.rename_delete()

      assert state.rename_value == "note.txt"
      assert state.rename_caret == 4
    end

    test "Delete at the end of the name is a no-op" do
      state = renaming("notes.txt", 9)

      assert Reducer.rename_delete(state) == state
    end

    test "the name can be cleared and retyped without the caret going negative" do
      state =
        Enum.reduce(1..12, renaming("notes.txt", 9), fn _, acc ->
          Reducer.rename_backspace(acc)
        end)

      assert state.rename_value == ""
      assert state.rename_caret == 0
      assert Reducer.rename_insert(state, "x").rename_value == "x"
    end
  end
end
