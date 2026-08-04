# Bug 002 — Menubar deselect: Escape doesn't close icon-menu dropdown

**Status:** PRD **Severity:** High **Filed:** 2026-04-22 (HEAD `fb15316`)

## Symptom

Escape with an icon-menu dropdown open (F/E/V/?) does not close it. Dropdown stays drawn, icon stays active+hover. All mouse paths close cleanly — only Escape fails.

## Repro (scenic_mcp port **9997**, not 9992)

**V1 — Keyboard (PRIMARY) ✗** `escape`, `move(200,500)`, `click(1558,17)` (`:icon_menu_file`), `send_keys("escape")`. Dropdown still visible (`New Buffer`…); F still in `icon_active_bg`. 5/5.

**V2 — Mouse toggle-close (SECONDARY) ✗** `click(1558,17)` open, `click(1558,17)` toggle-close. F retains `icon_hover_bg` until cursor leaves icon bar — toggle clears `active_menu`/`hovered_item`, leaves `hovered_menu`.

**V3 — Mouse move-away (NO REPRO) ✓** Open File, `move(200,500)`. F clears. Brief's "not enough cursor_pos events" hypothesis disproved.

## Root cause

`scenic-widget-contrib/lib/components/icon_menu/reducer.ex:25`:

```elixir
def process_input(%State{} = state, {:key, {"escape", _mods, _action}}) do
```

Scenic delivers `{:key, {atom, key_state, mods}}` (cf. `text_field/reducer.ex:101`: `{:key, {:key_esc, key_state, _mods}}`). Clause never matches; Escape → noop at `reducer.ex:29`. V2: toggle-close at `reducer.ex:91-93` omits `hovered_menu: nil`.

## Fix sketch

1. `reducer.ex:25` → `{:key, {:key_esc, key_state, _mods}} when key_state > 0`, route to `handle_escape/1`.
2. Add `hovered_menu: nil` to toggle-close map at `reducer.ex:93`.
3. Apply in `../scenic-widget-contrib` — `deps/scenic_widget_contrib/` is stale.

## Acceptance gate

`test/spex/quillex/21_menu_escape_close_spex.exs` scenario **"Escape closes open File dropdown"**: `click_element("icon_menu_file")` → `send_keys("escape", [])` → `refute Query.text_visible?("New Buffer")`. Plus SWC unit: `Reducer.process_input(%State{active_menu: :file}, {:key, {:key_esc, 1, []}})` → `{:noop, %State{active_menu: nil, hovered_menu: nil, hovered_item: nil}}`.
