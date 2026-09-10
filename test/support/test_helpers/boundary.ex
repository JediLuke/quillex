defmodule Quillex.TestHelpers do
  @moduledoc """
  Boundary for test helper modules.

  These helpers provide viewport query utilities built on top of Scenic's
  semantic layer. They do NOT access Quillex internals — they only query
  the viewport through Scenic's public API.

  Exported to the `Quillex.Spex` boundary so spex tests can use them
  for assertions about what's visible on screen.

  `ScenicMcp` is intentionally not listed in `deps:`. Boundary enforces
  relationships within this Mix application; external testing applications
  are ordinary library dependencies, not Quillex boundaries.

  This boundary and its exports live under `test/support/test_helpers`, which
  is included only by `elixirc_paths(:test)`. Keeping them outside `lib/`
  prevents test automation, assertions, and Scenic inspection utilities from
  shipping in production releases or appearing in the application's HexDocs.
  """
  use Boundary,
    deps: [Quillex],
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
      SemanticProbe,
      Oracle,
      # The integration spex's shared vocabulary — open a file, switch tabs,
      # read what the editor shows. It was written into the helpers and never
      # listed here, so every spex that imported it compiled with a boundary
      # warning: 185 of them, the bulk of the noise in a test build.
      Integration
    ]
end
