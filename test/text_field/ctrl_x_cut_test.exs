defmodule Quillex.TextField.CtrlXCutTest do
  @moduledoc """
  Regression guards for bug 001 — Ctrl+X after mouse-drag selection.

  Full write-up: `docs/bugs/001_ctrl_x_mouse_select_crash.md`. In brief:

  Before the fix the TextField reducer's Ctrl+X clause guarded on
  `%State{focused: true, selection: selection} when selection != nil`. In
  buffer-backed mode the TextField's local `state.selection` is only
  populated when the buffer process broadcasts `{:buf_state_changes, ...}`
  back to TextField and `TextField.handle_info/2` mirrors it — which races
  against the user's next keystroke after a mouse-drag. If Ctrl+X fired
  while `state.selection` was still `nil`, the guard didn't match and the
  keystroke fell through to the catch-all (`nil`). The result was silent
  data loss.

  The fix (bug 001, Branch a, PREFERRED path) routes Ctrl+X and Ctrl+C
  through unconditionally in `input_to_buffer_action/2`, returning
  `{:cut, :selection}` and `{:copy, :selection}` respectively. The buffer
  controller is now the single source of truth for the selection shape;
  `Quillex.Buffer.Process.Reducer.process/2` no-ops cleanly when the
  buffer itself has no selection.

  These tests pin that contract at the reducer layer:

    * Ctrl+X with the `%{start:, end:}` map-shape (mouse-drag selection)
      still returns `{:cut, :selection}`.
    * Ctrl+X with a tuple-pair `{start, end}` shape (legacy form that may
      have leaked into TextField's local mirror) still returns
      `{:cut, :selection}` — i.e. the reducer must no longer inspect the
      shape at all.
    * Ctrl+X with `selection: nil` also returns `{:cut, :selection}` and
      must not crash. The buffer will no-op downstream.
    * Ctrl+C mirrors the same behaviour for `{:copy, :selection}` as a
      light smoke-check that the two clauses are consistent.

  We do NOT test an unfocused-with-selection case: the PRD's hypothesis
  (b) was disproved. The `focused: true` guard remains and unfocused
  keystrokes correctly fall through the reducer. See PRD §"Root cause
  (confirmed)".
  """

  use ExUnit.Case, async: true

  alias ScenicWidgets.TextField.State
  alias ScenicWidgets.TextField.Reducer

  # Build a minimal State with `focused: true` so the Ctrl+X clause can match.
  # Any extra fields (lines, cursor, ...) are irrelevant to this clause — the
  # fix makes it pure pattern-match on `focused` alone.
  defp state(overrides) do
    defaults = [
      focused: true,
      input_mode: :buffer_backed,
      lines: ["hello world"],
      cursor: {1, 12},
      selection: nil,
      id: :test_tf
    ]

    struct(State, Keyword.merge(defaults, overrides))
  end

  # ---------------------------------------------------------------------------
  # Ctrl+X — must route to {:cut, :selection} regardless of local selection
  # ---------------------------------------------------------------------------

  describe "input_to_buffer_action/2 — Ctrl+X (key_x, ctrl)" do
    test "with mouse-shape %{start:, end:} selection returns {:cut, :selection}" do
      # Mouse-drag selection is broadcast back from the buffer in this shape
      # (see Quillex.Buffer.Process.Reducer for {:select_range, ...}).
      s = state(selection: %{start: {1, 7}, end: {1, 12}})
      assert Reducer.input_to_buffer_action(s, {:key, {:key_x, 1, [:ctrl]}}) ==
               {:cut, :selection}
    end

    test "with tuple-pair {start, end} legacy selection returns {:cut, :selection}" do
      # Older code sometimes mirrored selection as a pair of tuples. The fixed
      # reducer must not inspect the shape at all — pattern match succeeds and
      # the action tuple is returned. If the reducer regressed to a guard like
      # `when selection != nil`, this would still pass; the real discriminator
      # is the nil-selection test below plus the mouse-shape test above.
      s = state(selection: {{1, 7}, {1, 12}})
      assert Reducer.input_to_buffer_action(s, {:key, {:key_x, 1, [:ctrl]}}) ==
               {:cut, :selection}
    end

    test "with selection: nil returns {:cut, :selection} (no crash, no guard)" do
      # This is the regression-critical case: before the fix the Ctrl+X clause
      # demanded `selection != nil` and this input fell through to the
      # catch-all `nil` — the user's keystroke was silently dropped even
      # though the buffer had a live selection of its own. With the fix, the
      # action is produced regardless; the buffer will no-op if IT also has
      # no selection.
      s = state(selection: nil)
      assert Reducer.input_to_buffer_action(s, {:key, {:key_x, 1, [:ctrl]}}) ==
               {:cut, :selection}
    end

    test "unfocused TextField still returns nil for Ctrl+X (fallback, not a crash)" do
      # The `focused: true` guard is preserved. Unfocused keystrokes fall
      # through to the catch-all `input_to_buffer_action(_, _) -> nil` —
      # confirming focus is still the gate for this clause and that no
      # crash occurs on unfocused Ctrl+X.
      s = state(focused: false, selection: %{start: {1, 1}, end: {1, 6}})
      assert Reducer.input_to_buffer_action(s, {:key, {:key_x, 1, [:ctrl]}}) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Ctrl+C — smoke-check that copy mirrors cut
  # ---------------------------------------------------------------------------

  describe "input_to_buffer_action/2 — Ctrl+C (key_c, ctrl)" do
    test "with mouse-shape selection returns {:copy, :selection}" do
      s = state(selection: %{start: {1, 7}, end: {1, 12}})
      assert Reducer.input_to_buffer_action(s, {:key, {:key_c, 1, [:ctrl]}}) ==
               {:copy, :selection}
    end

    test "with selection: nil returns {:copy, :selection} (same rationale as cut)" do
      s = state(selection: nil)
      assert Reducer.input_to_buffer_action(s, {:key, {:key_c, 1, [:ctrl]}}) ==
               {:copy, :selection}
    end
  end
end
