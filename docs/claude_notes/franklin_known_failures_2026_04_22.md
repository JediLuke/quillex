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
