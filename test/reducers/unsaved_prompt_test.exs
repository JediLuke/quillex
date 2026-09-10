defmodule Quillex.RootScene.UnsavedPromptTest do
  use ExUnit.Case, async: true

  alias Quillex.RootScene
  alias Quillex.RootScene.State, as: RootState
  alias Quillex.Buffer.Ref

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

  defp buf_ref(dirty?, external_change \\ nil) do
    %Ref{
      uuid: "uuid-" <> Integer.to_string(:erlang.unique_integer([:positive])),
      name: "untitled",
      dirty?: dirty?,
      external_change: external_change
    }
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

    # The hole this covers: a file deleted underneath an unedited buffer leaves
    # that buffer holding the only copy of the content, and dirty? is false, so
    # every close path used to throw it away without a word.
    test "clean buffer whose file was deleted on disk → {:show_prompt, ...}" do
      s = state()
      br = buf_ref(false, :deleted)

      assert {:show_prompt, ^br, new_state} = RootScene.decide_close(s, br)
      assert new_state.show_unsaved_prompt == true
      assert new_state.pending_close_buf_ref == br
    end

    # Dirty AND deleted is one situation, not two: a single prompt, never a
    # second dialog stacked behind the first.
    test "dirty buffer whose file was deleted on disk → a single {:show_prompt, ...}" do
      s = state()
      br = buf_ref(true, :deleted)

      assert {:show_prompt, ^br, new_state} = RootScene.decide_close(s, br)
      assert new_state.show_unsaved_prompt == true
      assert new_state.pending_close_buf_ref == br
    end

    # :modified is not a data-loss case — the file is still on disk, so nothing
    # unrecoverable is at stake. (In practice ExternalFileSync only ever marks
    # :modified on a buffer that is already dirty; a clean one is reloaded.)
    test "clean buffer modified on disk → {:close, buf_ref}, no prompt" do
      s = state()
      br = buf_ref(false, :modified)

      assert {:close, ^br} = RootScene.decide_close(s, br)
    end

    test "dirty buffer modified on disk still prompts, on the dirty grounds" do
      s = state()
      br = buf_ref(true, :modified)

      assert {:show_prompt, ^br, _new_state} = RootScene.decide_close(s, br)
    end
  end

  # ---------------------------------------------------------------------------
  # Quillex.Buffer.unsaved?/1 — the single definition of "this content is not
  # on disk", shared by the close decision, the preview-tab logic and quit.
  # ---------------------------------------------------------------------------
  describe "Quillex.Buffer.unsaved?/1" do
    test "clean, untouched buffer is disposable" do
      refute Quillex.Buffer.unsaved?(buf_ref(false))
    end

    test "dirty buffer is not disposable" do
      assert Quillex.Buffer.unsaved?(buf_ref(true))
    end

    test "clean buffer deleted on disk is not disposable" do
      assert Quillex.Buffer.unsaved?(buf_ref(false, :deleted))
    end

    test "dirty buffer deleted on disk is not disposable" do
      assert Quillex.Buffer.unsaved?(buf_ref(true, :deleted))
    end

    test "clean buffer modified on disk IS disposable — the file still exists" do
      refute Quillex.Buffer.unsaved?(buf_ref(false, :modified))
    end
  end

  # ---------------------------------------------------------------------------
  # Preview tabs. Reusing the preview slot closes the buffer sitting in it with
  # no user action at all, so a deleted-on-disk buffer must stop being
  # provisional the moment it is marked — the same promotion an edit earns it.
  # ---------------------------------------------------------------------------
  describe "surviving_preview/2" do
    test "a clean preview buffer stays provisional" do
      br = buf_ref(false)
      assert RootScene.surviving_preview(br.uuid, [br]) == br.uuid
    end

    test "an edited preview buffer is promoted out of the preview slot" do
      br = buf_ref(true)
      assert RootScene.surviving_preview(br.uuid, [br]) == nil
    end

    test "a preview buffer deleted on disk is promoted out of the preview slot" do
      br = buf_ref(false, :deleted)
      assert RootScene.surviving_preview(br.uuid, [br]) == nil
    end

    test "a preview buffer modified on disk stays provisional" do
      br = buf_ref(false, :modified)
      assert RootScene.surviving_preview(br.uuid, [br]) == br.uuid
    end

    test "a buffer that is gone leaves no preview slot behind" do
      assert RootScene.surviving_preview("uuid-vanished", []) == nil
      assert RootScene.surviving_preview(nil, []) == nil
    end
  end
end
