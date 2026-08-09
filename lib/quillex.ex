defmodule Quillex do
  @moduledoc """
  Quillex is a programmer-oriented text editor written in Elixir and rendered
  with Scenic.

  The normal desktop application provides a graphical, multi-buffer editing
  environment with file navigation, search and replace, undo and redo,
  selections, configurable editor views, and mouse and keyboard interaction.
  Quillex can also supply its buffer backend to another application or run
  without its own graphical viewport; see `QuillEx.App` for the standalone,
  embedded, and headless runtime contracts.

  ## Programmatic interface

  `Quillex.Buffer` is the primary API for creating, opening, listing,
  activating, reading, editing, saving, reloading, and closing documents.
  External callers identify a document with `Quillex.Buffer.Ref` and receive
  immutable document state as `Quillex.Buffer.Snapshot`; internal GenServer
  state is not part of that contract. `Quillex.API.FileAPI` provides the
  active-editor-oriented file operations used by interactive and IEx clients.

  ## Architectural boundary

  This module is intentionally small because it is also the root
  [Boundary](https://hexdocs.pm/boundary/) declaration for the project.
  `top_level?: true` assigns the application modules under the `Quillex`
  namespace to this boundary unless a more specific child boundary classifies
  them. Boundary checks then reject dependencies that have not been declared
  and prevent other boundaries from reaching through the exported surface into
  implementation modules.

  The `exports` below are architectural visibility rules between boundaries;
  they are not, by themselves, a promise that every exported module is a stable
  end-user API. In particular, `Quillex.RadixCache.ViewStore` and
  `Quillex.PerfMonitor` are exported seams used by the test-helper and
  observability boundaries. The stable document-facing contract begins with
  `Quillex.Buffer`, `Quillex.Buffer.Ref`, and `Quillex.Buffer.Snapshot`.

  Keeping this declaration at the product's top-level module gives HexDocs a
  useful landing page while keeping the dependency rules close to the namespace
  they govern.
  """

  use Boundary,
    top_level?: true,
    deps: [],
    exports: [
      API.FileAPI,
      # Public buffer setup/inspection contract. Interaction scenarios still
      # exercise the UI and never use this as a fallback for a failed gesture.
      Buffer,
      # View settings — TestHelpers.AppReset closes the file navigator so a
      # spex starts with a known LAYOUT. Left open by an earlier file, it
      # shifts the editor pane 250px right, and any test clicking at a fixed
      # x then clicks the sidebar instead of the document.
      RadixCache.ViewStore,
      # Diagnostics access for TestHelpers.Perf (performance-budget spex)
      PerfMonitor
    ]
end
