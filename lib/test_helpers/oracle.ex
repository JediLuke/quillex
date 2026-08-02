defmodule Quillex.TestHelpers.Oracle do
  @moduledoc """
  Pure-model oracle for conformance spex (Roadmap 1.0, Phase 4b layer 2).

  The backend Reducer is pure — it already IS the formal model of the
  editor. This helper folds semantic actions through it directly, with no
  processes, stores, or rendering involved. A conformance spex applies the
  same operations to the live GUI (as keystrokes) and to this oracle (as
  actions), then asserts both worlds agree.

  What that proves: the entire delivery pipeline — keymap translation,
  PaneStore dispatch, Buffer.Process, PubSub publish, TextField state sync,
  semantic rendering — implements the pure model with no lost, duplicated,
  or reordered operations. (Exactly the bug class of the 2026-07-31 QA
  findings: double-delivery, focus leaks, stale state.)
  """

  alias Quillex.Buffer.Process.Reducer
  alias Quillex.Structs.BufState

  @doc "A fresh empty document, as the GUI's File → New produces."
  def new_document do
    BufState.new(%{})
  end

  @doc "Fold a list of semantic actions through the pure Reducer."
  def apply_actions(%BufState{} = buf, actions) when is_list(actions) do
    Enum.reduce(actions, buf, &Reducer.process(&2, &1))
  end

  @doc "The document text as the GUI's semantic layer reports it."
  def text(%BufState{data: lines}), do: Enum.join(lines, "\n")

  @doc "The cursor as `{line, col}`."
  def cursor(%BufState{cursors: [%{line: l, col: c} | _]}), do: {l, c}
end
