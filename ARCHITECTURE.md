# Quillex Architecture

Quillex is a text editor built on [Scenic](https://github.com/ScenicFramework/scenic),
and deliberately also a **reference implementation** of a pattern: redux-style
stores on Scenic's retained PubSub, with a hard line between a frontend that
owns raw input and a backend that only ever sees semantic actions.

This document is the map. The doctrine lives in `AGENTS.md` (State
Architecture section) and `Quillex-BasePrompt.md`; the store contract that
makes the TextField reusable is documented in `ScenicWidgets.TextField`'s
moduledoc (in `../scenic-widget-contrib`).

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
| `Quillex.RadixCache.ViewStore` | `:radix_view` | editor settings, file-nav flags, status message + its clear-timer |

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
