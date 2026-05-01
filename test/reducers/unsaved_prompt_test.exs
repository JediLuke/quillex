defmodule QuillEx.RootScene.UnsavedPromptTest do
  use ExUnit.Case, async: true

  alias QuillEx.RootScene
  alias QuillEx.RootScene.State, as: RootState
  alias Quillex.Structs.BufState.BufRef

  # Build a RootScene.State skeleton that satisfies the struct invariants.
  # The `decide_close/2` function only reads and writes the dirty-prompt
  # fields, so the other fields can stay at defaults.
  defp state(overrides \\ %{}) do
    base = %RootState{
      show_unsaved_prompt: false,
      pending_close_buf_ref: nil
    }

    Map.merge(base, overrides)
  end

  defp buf_ref(dirty?) do
    %BufRef{uuid: "uuid-" <> Integer.to_string(:erlang.unique_integer([:positive])),
            name: "untitled",
            mode: :edit,
            dirty?: dirty?}
  end

  describe "decide_close/2" do
    test "dirty buffer → {:show_prompt, buf_ref, state} with show_unsaved_prompt and pending_close_buf_ref set" do
      s = state()
      br = buf_ref(true)

      assert {:show_prompt, ^br, new_state} = RootScene.decide_close(s, br)
      assert new_state.show_unsaved_prompt == true
      assert new_state.pending_close_buf_ref == br
    end

    test "clean buffer → {:close, buf_ref}; does NOT set prompt flags" do
      s = state()
      br = buf_ref(false)

      assert {:close, ^br} = RootScene.decide_close(s, br)
      # Calling the pure decision must not mutate the caller's state reference;
      # the production caller will just dispatch the close action.
      assert s.show_unsaved_prompt == false
      assert s.pending_close_buf_ref == nil
    end

    test "nil active buffer → :noop and state is unchanged" do
      s = state()

      assert :noop = RootScene.decide_close(s, nil)
      assert s.show_unsaved_prompt == false
      assert s.pending_close_buf_ref == nil
    end
  end
end
