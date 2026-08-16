defmodule Quillex.Spex do
  @moduledoc """
  The restricted architectural boundary for Quillex's black-box Spex tests.

  `Quillex` is the application's top-level production boundary. It owns the
  product namespace and distinguishes its explicitly exported surface from its
  private scenes, stores, reducers, processes, and other implementation code.
  This module does not replace or compete with that boundary. It represents a
  deliberately less-privileged consumer of it.

  ## Why UI tests need their own boundary

  Spex scenarios are intended to exercise the editor as a person does: through
  real keyboard and pointer input, followed by observations of Scenic's rendered
  and semantic output. Their value would be undermined if a scenario could fix
  its own setup, or make an assertion pass, by calling an internal reducer,
  GenServer, or RootScene function directly.

  Spex module names normally begin with `Quillex`, so Boundary's namespace-based
  classification would otherwise place them inside the production `Quillex`
  boundary. That would give a purported black-box test the same architectural
  privileges as the code it is testing.

  The Spex compiler prevents that by forcing every matching scenario into this
  boundary. The configuration lives in `mix.exs`:

      spex: [
        pattern: "test/spex/**/*_spex.exs",
        boundary: Quillex.Spex
      ]

  A Spex may therefore use only:

  * exports from the top-level `Quillex` boundary, which form the approved
    application-facing surface; and
  * exports from `Quillex.TestHelpers`, which wrap Scenic automation and
    diagnostics without granting arbitrary access to product internals.

  If a Spex references a non-exported Quillex implementation module, Boundary
  reports a compile-time violation. That failure is intentional evidence that
  the scenario has crossed from observing behavior into depending on how the
  behavior is implemented.

  ## Why external testing libraries are not dependencies here

  Boundary checks relationships between boundaries in this Mix application.
  `ScenicMcp`, `SexySpex`, ExUnit, and standard-library modules belong to other
  applications and are outside that enforcement model, so they do not belong
  in `deps:`. Listing them as if they were local boundaries only produces
  misleading "unknown boundary" warnings.

  ## Why this module lives in `test/support`

  This boundary exists solely to compile and police tests. Keeping it under
  `test/support` prevents a test-only architectural declaration from appearing
  in the production library or generated Hex documentation. The test Elixir
  paths compile support modules before the Spex compiler processes scenario
  files, so `Quillex.Spex` is available when classification occurs.
  """

  use Boundary,
    deps: [Quillex, Quillex.TestHelpers],
    exports: []
end
