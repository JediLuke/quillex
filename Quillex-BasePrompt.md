# Quillex Base Prompt

## Project Overview

**Quillex** is a text editor application built in Elixir using the Scenic graphics framework. It's part of a larger ecosystem of local development dependencies that are actively being developed together.

## Critical: Local Dependency Ecosystem

This project has **local path dependencies** that are actively developed alongside Quillex. When working on Quillex, changes often need to be made in these underlying libraries.

### Directory Structure
```
/home/luke/workbench/flx/
├── quillex/                    # THIS APP - the text editor
├── scenic/                     # DEPENDENCY - forked Scenic framework
├── scenic_driver_local/        # DEPENDENCY - Scenic window driver
├── scenic-widget-contrib/      # DEPENDENCY - TextField, TabBar, etc.
├── spex/                       # DEPENDENCY - SexySpex test framework
└── scenic_mcp_experimental/    # DEPENDENCY - MCP integration for testing
```

### Key Dependencies (from mix.exs)
```elixir
# Core framework - LOCAL FORK
{:scenic, path: "../scenic", override: true}
{:scenic_driver_local, path: "../scenic_driver_local", override: true}

# Widgets - LOCAL FORK (TextField, TabBar, IconMenu, FilePicker)
{:scenic_widget_contrib, path: "../scenic-widget-contrib"}

# Testing - LOCAL
{:sexy_spex, path: "../spex", only: [:test, :dev]}
{:scenic_mcp, path: "../scenic_mcp_experimental", only: [:dev, :test]}
```

## Development Philosophy

### Goal: Generic, Reusable Functionality

When implementing features in Quillex, **prefer creating generic functionality in dependency repos** rather than one-off solutions in Quillex:

- **TextField improvements** → `scenic-widget-contrib`
- **Scenic framework changes** → `scenic` fork
- **Test tooling improvements** → `spex` or `scenic_mcp`
- **Layout/widget utilities** → Could go in `scenic-widget-contrib` or create new lib

### Working Across Repos

A typical development session might involve:
1. Discovering a limitation while working on Quillex
2. Implementing a generic solution in scenic-widget-contrib or scenic
3. Using that new capability in Quillex
4. Testing the integrated behavior with spex tests

## Architecture Overview — RadixCache (redux-style stores on Scenic.PubSub)

> Full topology + flow diagrams: **`ARCHITECTURE.md`** (repo root).

Quillex uses the **RadixCache pattern** (shared with the sibling merlinex
app): GenServer stores organized by *data domain*, publishing full state
snapshots on retained `Scenic.PubSub` sources. Components hydrate instantly
from ETS (`get/1`) and self-update on publishes (`subscribe/1` delivers the
retained value, so a late subscriber can never miss state).

```
             dispatch (cast action fns)                    snapshots (Scenic.PubSub)
  GUI ────────────────────────────────────▶ Stores ────────────────────────────────▶ GUI
                                              │
   Quillex.Buffer.Process (one per buffer)    │  :"radix_buf_<uuid>"  → TextField
   Quillex.Buffer.BufferManager               │  :radix_buffers       → RootScene (tabs, active)
   Quillex.RadixCache.ViewStore               │  :radix_view          → RootScene (chrome)
```

- **Store = GenServer per data domain.** Public selector fns wrap
  `Scenic.PubSub.get`; public action fns are casts (never block the GUI);
  the `handle_cast`/`handle_info` clauses ARE the reducers; every mutation
  funnels through one `publish` commit point.
- **Boot order**: `Quillex.RadixCache.Supervisor` starts `Scenic.PubSub`
  *before* the buffer tree and before Scenic (the scenic fork skips its own
  PubSub start when one is running). Source atoms are minted only in
  `Quillex.RadixCache.Sources`.
- **The typing path never touches RootScene**: TextField (`:buffer_backed`)
  casts actions straight to `Buffer.Process` (addressed by via-tuple) and
  re-renders itself from that buffer's published snapshots.
- **Edge-triggered metadata**: `Buffer.Process` casts `{:buffer_meta, ...}`
  to BufferManager only when `dirty?`/`name` transition, so tab-bar dirty
  dots are reactive without per-keystroke list publishes. No store debounces
  — an editor publishes every reduce immediately.
- **Never a catch-all above `{{Scenic.PubSub, :data}, ...}` clauses** — it
  silently swallows store updates (known merlinex footgun).

### Key Modules

| Module | Location | Purpose |
|--------|----------|---------|
| `QuillEx.App` | `lib/app.ex` | Application entry, supervision tree |
| `Quillex.RadixCache.Supervisor` | `lib/radix_cache/supervisor.ex` | Starts Scenic.PubSub + stores |
| `Quillex.RadixCache.Sources` | `lib/radix_cache/sources.ex` | Mints all store source atoms |
| `Quillex.RadixCache.ViewStore` | `lib/radix_cache/view_store.ex` | UI-chrome store (:radix_view) |
| `Quillex.RadixCache.PaneStore` | `lib/radix_cache/pane_store.ex` | Pane store (:radix_pane_main): follows active buffer, forwards actions |
| `BufferManager` | `lib/buffers/exec/buffer_manager.ex` | Buffer lifecycle + buffer-list store (:radix_buffers) |
| `Buffer.Process` | `lib/buffers/buf_proc/buffer_process.ex` | Per-buffer store (action reduce loop) |
| `BufState` | `lib/buffers/buf_proc/buf_state.ex` | Buffer data structure |
| `QuillEx.RootScene` | `lib/gui/scenes/root/qlx_root_scene.ex` | Root scene: input routing, snapshot rendering, dialog choreography |
| `Renderizer` | `lib/gui/scenes/root/qlx_root_scene_renderizer.ex` | State-diff → graph (delete+recreate z-order) |
| `Quillex.PerfMonitor` | `lib/utils/perf_monitor.ex` | Render/handler timing telemetry |

### State Ownership
- **Per-buffer text state** (lines, cursors, selection, undo/redo, search):
  `Buffer.Process`, published on `:"radix_buf_<uuid>"`.
- **Buffer list + active buffer + dirty flags**: `BufferManager`, published
  on `:radix_buffers`. Lifecycle and list-state share one process on purpose
  — open/close IS a list change; splitting them would race.
- **Editor settings, file-nav flags, status message**: `ViewStore`,
  published on `:radix_view` (the status auto-clear timer lives in the store).
- **Search-bar/dialog flags**: scene-owned transient interaction state (see
  `QuillEx.RootScene.State` moduledoc for the doctrine).

### Process Model
- One `BufferManager` GenServer: lifecycle + buffer-list store
- One `Buffer.Process` GenServer per open buffer: the buffer's store
- One `ViewStore` GenServer: UI chrome store
- Stores publish → subscribed scenes/components re-render themselves

## Text Editor Features

### Current Capabilities
- Multi-line text editing with cursor
- Cursor movement (arrows, Home, End)
- Text selection (Shift+arrows, Ctrl+A)
- Clipboard operations (copy/cut/paste)
- Multiple buffers with tab switching
- Line numbers (configurable)
- Word wrap (configurable)
- File picker dialog

### Buffer Data Format
- Text stored as `["line1", "line2", ...]` (list of strings)
- Empty buffer is `[""]`
- Cursor uses 1-indexed line/column

### Input Flow
```
Typing:     Scenic input → TextField (:buffer_backed) → cast {:action, ...}
              → Buffer.Process reduce → publish :"radix_buf_<uuid>"
              → TextField handle_info → push_graph   (RootScene not involved)

Shortcuts:  Scenic :key input → RootScene → store action fn (cast)
              → store publishes → RootScene snapshot clause → Renderizer → push
```

## Testing

### SexySpex (BDD Testing)
Location: `test/spex/quillex/`

```elixir
# Run all spex tests
mix test test/spex/

# Run specific test file
mix test test/spex/quillex/02_basic_text_editing_spex.exs
```

### ScenicMCP Integration
Tests use MCP tools to interact with the running app:
- `send_keys/2` - Send keyboard input
- `take_screenshot/0` - Capture current screen
- `inspect_viewport/0` - Get UI structure
- `click_element/1` - Click by semantic ID
- `find_clickable_elements/0` - Discover interactive elements

### Test Files
- `01_app_launch_spex.exs` - Startup verification
- `02_basic_text_editing_spex.exs` - Core editing operations
- `03_buffer_management_spex.exs` - Buffer operations

## Configuration

### Test Config (`config/test.exs`)
```elixir
config :quillex,
  test_window_size: {2000, 1200},  # Wide window prevents wrapping
  default_buffer_mode: :edit

config :scenic_mcp, port: 9987  # Different port for tests
```

### Editor Settings (in RootScene.State)
- `show_line_numbers` - Display line numbers
- `word_wrap` - Enable word wrapping
- `show_file_picker` - Modal file dialog

## Common Development Tasks

### Adding a New Feature
1. Consider: Should this be generic (dependency repo) or Quillex-specific?
2. If generic: Implement in appropriate dependency, test there first
3. Add Quillex integration in RootScene/BufferPane
4. Add spex test scenario

### Working on TextField
```bash
cd ../scenic-widget-contrib
# Make changes to lib/scenic_widgets/text_field/...
# Changes immediately available in Quillex (path dependency)
```

### Debugging Scenic Rendering
- Use `mix scenic.run` for interactive testing
- Screenshots via `take_screenshot/0` in tests
- `inspect_viewport/0` gives text description of UI

### Adding New Actions
1. Define action in appropriate reducer
2. Implement handler in mutator
3. Wire up in RootScene or BufferPane
4. Add test coverage

## Key Files Quick Reference

| Purpose | File |
|---------|------|
| App entry | `lib/app.ex` |
| Main scene | `lib/gui/scenes/root/qlx_root_scene.ex` |
| UI rendering | `lib/gui/scenes/root/qlx_root_scene_renderizer.ex` |
| Buffer component | `lib/gui/components/buffer_pane/buffer_pane.ex` |
| Buffer manager | `lib/buffers/exec/buffer_manager.ex` |
| Buffer process | `lib/buffers/buf_proc/buffer_process.ex` |
| Buffer state | `lib/buffers/buf_proc/buf_state.ex` |
| Cursor struct | `lib/buffers/buf_proc/cursor.ex` |
| UI state | `lib/fluxus/radix/qlx_root_scene_state.ex` |
| UI reducer | `lib/fluxus/radix/qlx_root_scene_reducer.ex` |
| Config | `config/config.exs` |
| Dependencies | `mix.exs` |

## Running the Application

```bash
# Start the application
mix scenic.run

# Or with iex
iex -S mix

# Run tests
mix test

# Run spex tests specifically
mix test test/spex/
```

## Tips for AI Assistants

1. **Always check local dependencies first** - Issues might be in scenic-widget-contrib, not Quillex
2. **TextField is from scenic-widget-contrib** - Not a Quillex module
3. **Scenic uses OpenGL** - Graphics are primitives, not DOM
4. **State is immutable** - Follow reducer pattern for changes
5. **PubSub for communication** - Don't call GUI directly from buffer processes
6. **Path dependencies mean immediate updates** - No need to publish/fetch
7. **Consider genericness** - Would this feature benefit other Scenic apps?
