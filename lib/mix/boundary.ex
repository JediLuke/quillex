defmodule Quillex.Mix do
  @moduledoc """
  Boundary for QuillEx Mix tasks.

  Mix tasks reside in the `Mix.Tasks` namespace (not `Quillex.*`) so they
  cannot be classified automatically by the Boundary compiler. We use this
  boundary as a container and classify each mix task into it explicitly via
  `use Boundary, classify_to: Quillex.Mix`.
  """
  use Boundary, deps: [], exports: []
end
