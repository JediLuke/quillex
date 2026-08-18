# Quillex Architecture

Quillex is a text editor built on [Scenic](https://github.com/ScenicFramework/scenic),
and deliberately also a **reference implementation** of a pattern: redux-style
stores on Scenic's retained PubSub, with a hard line between a frontend that
owns raw input and a backend that only ever sees semantic actions.

This document is the map. The doctrine lives in `AGENTS.md` (State
Architecture section); the store contract that makes the TextField reusable is
documented in `ScenicWidgets.TextField`'s moduledoc (in
`../scenic-widget-contrib`). `docs/CODEBASE_TOUR.md` is the guided walk through
the code itself.

## Runtime ownership and public buffer contract

`config :quillex, runtime_mode:` selects `:standalone` or `:headless`. Only
standalone owns the Scenic viewport and its deferred-close coordinator.
Headless starts the backend services and keeps VM lifetime with the host.

External consumers use `Quillex.Buffer.Ref` for identity and
`Quillex.Buffer.Snapshot` for immutable document reads. Scroll offsets and
folds are pane-view state; they never dirty a document snapshot. BufferManager
alone owns canonical path identity, open-buffer lifecycle, and activation.

## The topology

```
                                THE STORE LINE
        FRONTEND (raw input lives here)   ║   BACKEND (only semantic actions cross)
                                          ║
  ┌─ Scenic ViewPort / Driver (GLFW) ─┐   ║
  │   keys · clicks · scroll          │   ║        RadixCache stores
  └──────────────┬───────────────────-┘   ║   (Scenic.PubSub: retained ETS,
                 │                        ║    get/1 instant, subscribe
    ┌────────────┴──────────────┐         ║    re-delivers retained value)
    ▼                           ▼         ║
┌─────────────────┐   ┌──────────────────┐║
│    RootScene    │   │    TextField     │║ {:action,[…]}  ┌─────────────────────┐
│  (thin shell)   │   │  :store_backed   │╫───────────────▶│      PaneStore      │
│                 │   │                  │║                │  :radix_pane_main   │
│ global shortcuts│   │ raw input        │◀╫───────────────│                     │
│ dialog + search │   │   → keymap       │║  snapshots     │ follows active buf, │
│   choreography  │   │   → actions      │║                │ sub-switches buffer │
│ snapshot render │   │ render(snapshot) │║                │ sources, republishes│
└───┬─────────▲───┘   └──────────────────┘║                └──────┬───────▲──────┘
    │         │                           ║           fwd actions│       │snapshots
    │         │  :radix_view              ║                      ▼       │
    │         │  :radix_buffers           ║   ┌──────────────────────────┴──┐
    │         └──────────────────────────╫────┤  Buffer.Process (× N open)  │
    │                                     ║   │  :"radix_buf_<uuid>"        │
    │ store action fns (casts)            ║   │  action → Reducer → publish │
    ├────────────────────────────────────╫───▶│  (lines·cursors·selection·  │
    │                                     ║   │   undo·search — the doc)    │
    │                                     ║   └──────┬──────────────────────┘
    │                                     ║          │ {:buffer_meta,…} edge-cast
    │                                     ║          ▼ (dirty?/name transitions only)
    │                                     ║   ┌─────────────────────────────┐
    ├────────────────────────────────────╫───▶│  BufferManager              │
    │                                     ║   │  :radix_buffers             │
    │                                     ║   │  lifecycle + list store:    │
    │                                     ║   │  open/close/activate,       │
    │                                     ║   │  [BufRef] + active_buf      │
    │                                     ║   └─────────────────────────────┘
    │                                     ║   ┌─────────────────────────────┐
    └────────────────────────────────────╫───▶│  ViewStore                  │
         put_child (surviving children)   ║   │  :radix_view                │
    ┌──────────┬───────────┬──────────┐   ║   │  settings · file nav ·      │
    ▼          ▼           ▼          ▼   ║   │  status msg (+ its timer)   │
 ┌───────┐ ┌────────┐ ┌─────────┐ ┌─────┐ ║   └─────────────────────────────┘
 │TabBar │ │IconMenu│ │SearchBar│ │Side │ ║
 │set_   │ │        │ │         │ │Nav  │ ║      (scene-owned, deliberately:
 │tabs ⇒ │ │        │ │         │ │     │ ║       search/dialog flags — 1-consumer
 │no re- │ │        │ │         │ │     │ ║       transient interaction state)
 │create │ └────────┘ └─────────┘ └─────┘ ║
 └───────┘                                ║
```

## The keystroke hot path

Note what it never touches:

```
key press ──▶ TextField ──cast──▶ PaneStore ──cast──▶ Buffer.Process
                 ▲                                        │ reduce
                 │                                        ▼
              render ◀── :radix_pane_main ◀── republish ◀─ publish :radix_buf_<uuid>

              (RootScene: not involved. TabBar: only if dirty? *transitions*.)
```

## A buffer switch — entirely a backend event

```
tab click ──▶ RootScene ──cast──▶ BufferManager ──publish──▶ :radix_buffers
                                                       │
              ┌────────────────────────────────────────┤
              ▼                                        ▼
         PaneStore                                RootScene
      unsub old source                       put_child(:tab_bar,
      get + sub new source                     {:set_tabs, …})
      republish on pane                              │
              │                                      ▼
              ▼                              TabBar updates in place
    TextField renders the new
    document — same process,
    same source, cursor rides
    the snapshot
```

## The input and focus model

The other thing a newcomer cannot infer from the tree. Scenic delivers input
two ways, and Quillex uses both — for different kinds of input, on purpose.

```
                        ┌──────────────────────────────┐
                        │  ViewPort / Driver (GLFW)    │
                        └───────┬──────────────┬───────┘
             POSITIONAL         │              │      NON-POSITIONAL
        (hit-tested: goes to    │              │   (broadcast: goes to EVERY
         whichever primitive    │              │    scene that asked for it)
         declared `input: […]`) │              │
                                ▼              ▼
              ┌──────────────────────┐   ┌──────────────────────────┐
              │ cursor_button        │   │ key · codepoint          │
              │ cursor_pos           │   │ (+ cursor_scroll, which  │
              │  → one component,    │   │  IS positional but must  │
              │    local coords      │   │  be requested, so every  │
              │                      │   │  handler bounds-checks   │
              │                      │   │  its own frame first)    │
              └──────────┬───────────┘   └────────────┬─────────────┘
                         │                            │
                         │                    every listener receives it,
                         │                    so each one GATES on focus:
                         ▼                            ▼
        ┌────────────────────────────┐   ┌──────────────────────────────┐
        │ RootScene routes FOCUS by  │   │ TextField  : focused? and    │
        │ where the click landed:    │   │              not overlay_open│
        │                            │   │ SideNav    : focused?        │
        │  x < sidebar width         │   │ SearchPane : focused?        │
        │    → focus side pane       │   │ SearchBar  : it is the       │
        │      blur buffer pane      │   │              overlay         │
        │  otherwise                 │   └──────────────────────────────┘
        │    → blur side pane        │
        │      focus buffer pane     │   Focus is granted by :focus /
        └────────────────────────────┘   :blur puts from the parent.
```

**Why two gates on the editor.** Focus is granted by an asynchronous message,
so between "an overlay opened" and "the editor learned it lost focus" there is
a window in which the dying pane is still eligible for keystrokes. That window
is not theoretical: the first characters of a search query used to be inserted
into the document. `{:set_overlay_open, true}` is a second, synchronous gate
that closes it.

**Why `request_input` and `input:` must not be mixed for the same type.** A
component that both requests `:cursor_button` and declares it on a primitive
receives every press twice. The same trap, in a different shape, is a component
with no `handle_update/3`: Scenic re-runs `init/3` on the same process when its
params change, which re-runs `request_input` — and every keystroke arrives
twice. The SearchPane was built with that bug and the symptom was a query field
reading `"needleneedle"`.

## The three properties that make it work

1. **The store line is absolute.** Every arrow crossing it is either a
   semantic action (frontend → backend) or a state snapshot (backend →
   frontend). Raw input never crosses. Vim keybindings, when they come, are a
   frontend keymap translating input → actions; the backend never knows which
   keybinding dialect produced an action.

2. **Process tree = pub/sub topology.** Every store is one GenServer that
   owns exactly one retained source and funnels every mutation through one
   publish commit point. The process IS the topic; death of the process ends
   the topic; supervisor restarts re-register (the scenic fork's PubSub
   cleanup fix makes this reliable).

3. **The GUI holds no long-lived state.** Components hydrate from ETS at
   init (`get/1` is instant; `subscribe/1` re-delivers the retained value, so
   nothing can be missed), self-update on publishes, and can be killed at any
   time. Parents message surviving children (`put_child` — e.g. TabBar's
   `{:set_tabs, …}`) instead of delete+recreating them; recreation churn was
   the source of most of the historical test flakiness.

## Store inventory

| Store | Source | Owns |
|---|---|---|
| `Quillex.Buffer.Process` (×N) | `:"radix_buf_<uuid>"` | one document: lines, cursors, selection, undo/redo, search |
| `Quillex.Buffer.BufferManager` | `:radix_buffers` | buffer lifecycle + list, active buffer, dirty flags (edge-cast) |
| `Quillex.RadixCache.PaneStore` | `:radix_pane_main` | what the pane displays; follows the active buffer, forwards actions |
| `Quillex.RadixCache.ViewStore` | `:radix_view` | editor settings, theme, file-nav flags, status message + its clear-timer |
| `Quillex.RadixCache.ProjectSearchStore` | `:radix_project_search` | project-wide search: query, scope, exclude globs, results, dismissals |
| `Quillex.RadixCache.HighlightStore` | `:radix_highlights` | token spans for the pane's document, for structural syntax marking |

`ProjectSearchStore` is the one store that subscribes to another's source: it
follows `:radix_pane_main` so that editing a file the results are showing
re-searches *that buffer* (debounced), and never the tree.

Source atoms are minted only in `Quillex.RadixCache.Sources`. Splits someday
= one more PaneStore with its own source; no other concept changes.

## Reuse story

`ScenicWidgets.TextField` (in `../scenic-widget-contrib`) is generic against
this pattern, not against quillex: in `:store_backed` mode it takes a
`source` (any Scenic.PubSub source publishing conforming snapshots) and a
`dispatch` (any cast target for `{:action, [...]}`). Quillex's per-buffer
stores are the reference implementation of that contract, and the PaneStore
is the reference "control plane" for hosts that switch documents behind a
stable pane.
