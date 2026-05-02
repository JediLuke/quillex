# Franklin — Known Deferred Spex Failures (snapshot 2026-04-22)

These failures were surfaced by the spex suite during cycle of 2026-04-22 and
are explicitly DEFERRED from that cycle's scope. One future cycle per entry,
following Perceive → Plan → Act → Adapt.

The unsaved-changes dialog cluster (`16_unsaved_close_prompt_spex.exs`) is
NOT listed here — it is being fixed in the current cycle.

## Deferred failures

| File | Line | One-line description |
|------|------|----------------------|
| `test/spex/quillex/07_integration_v1_spex.exs` | 430 | Large-file line count 338 vs 339 (may resolve when test-loosening revert lands) |
| `test/spex/quillex/07_integration_v1_spex.exs` | 686 | Close search bar → typing goes to buffer |
| `test/spex/quillex/07_integration_v1_spex.exs` | 1213 | Shift+Scroll horizontal scroll |
| `test/spex/quillex/07_integration_v1_spex.exs` | 1603 | Mouse click positions cursor (possible regression) |
| `test/spex/quillex/08_property_tests_spex.exs` | (2 failing) | Property-test failures — capture specific scenario names from next run |
| `test/spex/quillex/10_file_navigator_spex.exs` | 235 | Buffer pane layout with file nav |
| `test/spex/quillex/11_run_verification_spex.exs` | 243 | Status bar "unchanged on disk" message |
| `test/spex/quillex/13_menu_close_outside_click_spex.exs` | (race) | Scenic `[error]` logs during component init/shutdown — surfaced by `fail_on_error_logs: true` revert |
| `test/spex/quillex/15_word_navigation_spex.exs` | 375 | Plain Left from end of 'abc' |
| `test/spex/quillex/17_page_navigation_spex.exs` | (5 scenarios) | `wait_for_cursor_satisfying` timeouts |

## Cycle retro — Unsaved Changes dialog regression (2026-05-01)

**Root cause: Candidate A — stale `BufRef` snapshot.** The `BufRef` cached in
`scene.assigns.state.active_buf` (and in the per-tab `state.buffers` list used
by the tab-bar close handler) is only refreshed when RootScene actively
applies an action. In buffer-backed mode the TextField writes directly to
`Quillex.Buffer.Process` — when the user typed after the last action, the
authoritative `dirty?` flag in `Buffer.Process` flipped to `true` while the
RootScene snapshot remained `false`. `try_close_buffer/2` matched the
non-dirty clause and dispatched `{:close_buffer, ...}` immediately, so no
"Unsaved Changes" dialog ever made it into the graph. (Candidates B and C
were ruled out: no earlier-matching clause short-circuits Ctrl+W past the
dialog path, and `ScenicWidgets.ConfirmDialog.add_to_graph/3` is reachable
with the existing call signature.)

**Fix:** In `lib/gui/scenes/root/qlx_root_scene.ex`, `try_close_buffer/2` now
calls `refresh_buf_ref/1` to fetch the live `BufRef` from `Buffer.Process`
before deciding, and the decision is factored into a pure
`decide_close/2` so it can be unit-tested directly. Both call paths
(`Ctrl+W`/menu close → `try_close_active_buffer/1` and tab-bar close button
→ `handle_event({:tab_closed, _}, ...)` → `try_close_buffer/2`) flow through
the same fresh-read path. Unit coverage in
`test/reducers/unsaved_prompt_test.exs` exercises all three branches
(dirty, clean, nil). All 6 scenarios in
`test/spex/quillex/16_unsaved_close_prompt_spex.exs` pass.

## Cycle retro — Cursor preservation on buffer switch (2026-05-02)

**Root cause: Candidate B (refined) — sibling-overlay click bleeds into the
buffer-pane TextField.** In `:buffer_backed` mode the buffer-pane TextField
calls `request_input(scene, [:cursor_button, :cursor_pos, ...])`, which
delivers EVERY click in the viewport to its `handle_input/3` regardless of
where the click visually lands. The frame-only `State.point_inside?/2` guard
admits clicks that fall inside the buffer-pane rectangle even when a sibling
overlay (here, the IconMenu File-dropdown's "New" item at viewport y≈18) is
the click's intended recipient. The handler then calls
`State.click_to_cursor/2`, which clamps far-past-EOL coordinates to end-of-
line and dispatches `{:set_cursor, {1, 17}}` to `Buffer.Process` — silently
overwriting the user's keyboard-positioned cursor at col 5. When the user
switches away and back, the TextField faithfully reads the now-corrupted
buffer cursor and types `X` at col 17 instead of col 5. (Candidate A —
TextField re-init drops cursor — was ruled out: probes showed the new
TextField reads `buf_cursors=[col: 17]` from `Buffer.Process` and renders
exactly that. The buffer already held the wrong value before the re-init.
Candidate C — one-way cursor sync — was ruled out: every keyboard cursor
edit reaches `Buffer.Process` via `handle_buffer_backed_input` and the arrow
keys persist correctly; only the spurious click between key-input and the
spex assertion mutated the cursor.)

**Fix:** In
`/home/luke/workbench/flx/scenic-widget-contrib/lib/components/text_field/reducer.ex`,
`input_to_buffer_action/2` for `{:cursor_button, {:btn_left, 1, _, coords}}`
now gates the `point_inside?` branch on a new
`buffer_backed_overlay_click?/2` predicate. In `:buffer_backed` mode only,
clicks whose local x falls more than 4× font-size past the rendered text
content of the targeted line are treated as overlay-class noise and the
reducer returns `nil` — no `:set_cursor` dispatched, no cursor mutation.
`:direct` mode keeps its existing past-EOL → place-at-EOL affordance
unchanged (the new clause's second head returns `false`). The change is one
predicate plus one `if` guard — no other call sites touched.

**Tests:** `test/buffers/buffer_switch_preserves_cursor_test.exs` pins the
reducer-layer contract directly with two ExUnit cases — far-past-EOL click
in `:buffer_backed` mode produces no `:set_cursor`, and the same click in
`:direct` mode still does. Both spex scenarios in
`test/spex/quillex/04_view_settings_spex.exs` (line 370 "Cursor position is
preserved when switching buffers" and line 428 "Cursor preserved across
multiple buffer switches") now pass; the surrounding line-numbers / word-
wrap scenarios in the same file remain green. (this commit)

## Triage principles

- One failure per cycle. Single atomic commit.
- Never loosen the spex to make it pass. Fix the application code.
- If an entry here turns out to be a test bug (not an application bug), fix
  the test, note the reason in the commit, and remove the entry from this doc.

## How this doc is maintained

- Each cycle that closes a deferred failure REMOVES that row and references
  the fixing commit in the retro note.
- Each cycle that surfaces a NEW failure APPENDS a row.
- When the list reaches zero rows, delete the file and regenerate the
  strategic plan.
