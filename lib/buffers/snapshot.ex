defmodule Quillex.Buffer.Snapshot do
  @moduledoc """
  Immutable public read model for one buffer.

  View-only state such as scrolling and folds belongs to `PaneStore`, not in a
  document snapshot.
  """

  alias Quillex.Buffer.Ref

  @enforce_keys [:ref, :lines, :cursor]
  defstruct [:ref, :lines, :cursor, :selection, search: nil]

  @type position :: {pos_integer(), pos_integer()}
  @type t :: %__MODULE__{
          ref: Ref.t(),
          lines: [String.t()],
          cursor: position(),
          selection: %{start: position(), end: position()} | nil,
          search: map() | nil
        }

  @doc false
  def from_internal(state) do
    cursor = {state.cursor.line, state.cursor.col}

    %__MODULE__{
      ref: Ref.generate(state),
      lines: state.data,
      cursor: cursor,
      selection: state.selection,
      search: %{
        query: state.search_query,
        matches: state.search_matches,
        current_index: state.search_current_index
      }
    }
  end
end
