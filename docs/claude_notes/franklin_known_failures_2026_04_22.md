# Franklin — Known Deferred Spex Failures (snapshot 2026-04-22)

These failures were surfaced by the spex suite during cycle of 2026-04-22 and
are explicitly DEFERRED from that cycle's scope. One future cycle per entry,
following Perceive → Plan → Act → Adapt.

The unsaved-changes dialog cluster (`16_unsaved_close_prompt_spex.exs`) is
NOT listed here — it is being fixed in the current cycle.

## Deferred failures

| File | Line | One-line description |
|------|------|----------------------|
| `test/spex/quillex/04_view_settings_spex.exs` | 418 | Cursor preservation on buffer switch |
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
