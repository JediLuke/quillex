defmodule Quillex do
  use Boundary,
    top_level?: true,
    deps: [],
    exports: [
      API.FileAPI,
      # Buffer control surface — used by TestHelpers.BufferSwitcher to give
      # spex a deterministic buffer switch (a tab CLICK can be lost, and a
      # silently-failed switch makes every later assertion test the wrong
      # document). Same precedent as TestHelpers.FileOpener.
      Buffer,
      # Buffer lifecycle — used by TestHelpers.AppReset to return the editor
      # to a clean state between spex files WITHOUT clicking through menus
      # (a lost click makes a reset silently not happen).
      Buffer.BufferManager,
      # View settings — TestHelpers.AppReset closes the file navigator so a
      # spex starts with a known LAYOUT. Left open by an earlier file, it
      # shifts the editor pane 250px right, and any test clicking at a fixed
      # x then clicks the sidebar instead of the document.
      RadixCache.ViewStore,
      # Diagnostics access for TestHelpers.Perf (performance-budget spex)
      PerfMonitor,
      # The pure document model, exported as the ORACLE for model-based
      # conformance testing (see TestHelpers.Oracle and spex 25): the same
      # action vocabulary the GUI dispatches through the stores can be
      # folded directly, and the two worlds compared.
      Buffer.Process.Reducer,
      Structs.BufState
    ]
end
