defmodule Quillex.PublicBoundaryTest do
  use ExUnit.Case, async: true

  # Boundary records these aliases relative to the top-level boundary.
  @approved_exports [
    "Elixir.API.FileAPI",
    "Elixir.Buffer",
    "Elixir.RadixCache.ViewStore",
    "Elixir.PerfMonitor",
    # Seams the spex read through — stores, catalogues, palettes, pollers
    # and one pure menu builder. See the note above them in lib/quillex.ex.
    "Elixir.RadixCache.ProjectSearchStore",
    "Elixir.RadixCache.PaneStore",
    "Elixir.GUI.Palette",
    "Elixir.GUI.Theme",
    "Elixir.GUI.SearchPaneModel",
    "Elixir.Utils.SideNavThemes",
    "Elixir.Commands",
    "Elixir.Shortcuts",
    "Elixir.SettingsFile",
    "Elixir.Files.ExternalFileSync",
    "Elixir.Files.NavigatorTreeSync",
    "Elixir.Search.Backend.Elixir",
    "Elixir.RootScene.Renderizer"
  ]

  test "the public boundary does not expose implementation modules to tests" do
    boundary = Quillex.__info__(:attributes) |> Keyword.fetch!(Boundary) |> List.first()

    exports = Enum.map(boundary.opts[:exports], &Atom.to_string/1)
    assert exports == @approved_exports

    refute Enum.any?(exports, fn name ->
             String.contains?(name, ["BufferManager", "Process", "Reducer", "BufState"])
           end)
  end
end
