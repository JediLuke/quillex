defmodule Quillex.Search.Match do
  @moduledoc """
  One occurrence of a project-wide search query.

  `line` and `col` are 1-based; `col` counts graphemes, the same unit the
  editor's cursor uses, so a match can be handed straight to a buffer's
  cursor. `text` is the whole source line, `matched` the text that matched.
  """

  @enforce_keys [:path, :line, :col, :text, :matched]
  defstruct [:path, :line, :col, :text, :matched]

  @type t :: %__MODULE__{
          path: Path.t(),
          line: pos_integer(),
          col: pos_integer(),
          text: String.t(),
          matched: String.t()
        }
end
