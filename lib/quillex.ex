defmodule Quillex do
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
