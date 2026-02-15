# Repository Guidelines

## Project Structure & Module Organization
- `lib/` holds the application code, organized by domain (e.g., `gui/`, `buffers/`, `core/`, `utils/`).
- `test/` mirrors `lib/` with ExUnit tests plus support helpers in `test/support/` and `test/test_helpers/`.
- `assets/` contains static assets used by the Scenic UI.
- `config/` contains environment configuration; `mix.exs` defines app metadata and dependencies.
- `tools/` and `biblio/` store auxiliary scripts and notes; `_build/` and `deps/` are build artifacts.

## Build, Test, and Development Commands
- `mix deps.get` fetches dependencies (note: several are local path deps).
- `mix compile` compiles the project.
- `iex -S mix run` starts the app in dev mode (matches README guidance).
- `mix test` runs the full ExUnit suite.
- `mix format` formats `mix`, `config`, `lib`, and `test` sources per `.formatter.exs`.
- Spex runs require `SCENIC_LOCAL_TARGET=glfw` (cairo-gtk is currently broken for spex).
  Example: `SCENIC_LOCAL_TARGET=glfw MIX_ENV=test mix spex test/spex/quillex/01_app_launch_spex.exs`.

## Coding Style & Naming Conventions
- Elixir code uses standard `mix format` conventions; run it before committing.
- Indentation is two spaces (Elixir default).
- Module and file names follow Elixir conventions (e.g., `QuillEx.Foo` in `lib/foo.ex`).
- Test files use the `_test.exs` suffix and live under `test/`.

## Testing Guidelines
- The suite is ExUnit-based; property tests use StreamData in `test/property/`.
- Prefer small, focused tests near the relevant domain folder.
- Run `mix test` locally before opening a PR; add tests for bug fixes and core logic.

## Commit & Pull Request Guidelines
- Recent commit messages are short and informal (no strict convention observed). Keep them concise and descriptive.
- PRs should include: a brief summary, testing notes (`mix test` or scoped command), and screenshots for UI changes in Scenic.
- Link related issues or documents (e.g., `GEDIT_CLONE_ROADMAP.md`) when applicable.

## Local Dependencies & Setup Notes
- `mix.exs` uses local path dependencies for Scenic and related libraries; ensure sibling repos exist (e.g., `../scenic`, `../scenic_driver_local`).
- Scenic requires OpenGL system deps; follow the Scenic install docs before running.

## Scenic Rendering Patterns

### Z-Order Control via Full Rebuild
When building complex UIs with overlapping elements (dropdowns, modals, search bars), z-order must be carefully managed. In Scenic, primitives render in the order they're added to the graph - later = on top.

**Problem**: Adding/deleting/recreating primitives can corrupt z-order. When a component is deleted and recreated, it ends up at the END of the graph (on top), even if it should be behind other elements.

**Solution**: When any component needs recreation that affects layout, delete ALL components and recreate them in the correct z-order (bottom to top).

```elixir
# In renderizer:
def render(graph, scene, old_state, state) do
  needs_reorder = needs_buffer_pane_recreation?(old_state, state)

  if needs_reorder do
    # Delete all and recreate in correct z-order (bottom to top)
    graph
    |> Scenic.Graph.delete(:buffer_pane)   # bottom layer
    |> Scenic.Graph.delete(:search_bar)    # middle layer
    |> Scenic.Graph.delete(:tab_bar)       # top layer
    |> Scenic.Graph.delete(:icon_menu)     # top layer
    |> create_buffer_pane(state, frame)    # added first = bottom
    |> create_search_bar(state, frame)     # added second = middle
    |> create_tab_bar(state, frame)        # added last = top
    |> create_icon_menu(state, frame)      # added last = top
  else
    # Incremental updates - z-order preserved since no deletions
    graph
    |> maybe_update_search_bar(...)
    |> update_top_bar(...)
  end
end
```

**Key insight**: Trigger full rebuild when layout changes (search bar visibility, buffer switch, etc.) to ensure dropdowns render above buffer content. Incremental updates are safe when no components are deleted.

**Note**: Scenic.Graph.modify passes the primitive to its callback, NOT a sub-graph. You cannot add children to groups via modify - groups must be rebuilt entirely.
