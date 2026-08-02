defmodule Quillex.Spex do
  @moduledoc """
  Boundary for spex integration tests.

  ## Configuration

  This boundary is referenced in `mix.exs`:

      spex: [
        pattern: "test/spex/**/*_spex.exs",
        boundary: Quillex.Spex
      ]
  """
  use Boundary, deps: [Quillex, Quillex.TestHelpers, ScenicMcp, SexySpex], exports: []
end
