defmodule Quillex.TestHelpers do
  @moduledoc """
  Boundary for test helper modules.

  These helpers provide viewport query utilities built on top of Scenic's
  semantic layer. They do NOT access Quillex internals — they only query
  the viewport through Scenic's public API.

  Exported to the `Quillex.Spex` boundary so spex tests can use them
  for assertions about what's visible on screen.
  """
  use Boundary,
    deps: [Quillex, ScenicMcp],
    exports: [
      SemanticHelpers,
      TextAssertions,
      SceneHelpers,
      ScriptInspector,
      FileOpener,
      AppReset,
      ViewportResizer,
      Perf,
      Invariants,
      Oracle
    ]
end
