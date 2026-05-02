# Diagnosis: cursor-preservation failure (04_view_settings_spex.exs:418)

Date: 2026-05-02
Spex: `test/spex/quillex/04_view_settings_spex.exs:362` ("View Settings - Cursor Preservation")
Scenario: "Cursor position is preserved when switching buffers"

## Reproduced failure

Assertion message captured verbatim:

```
Cursor should have preserved position. 'X' should appear after 'Line'.
Text: untitled untitled-2 1 2 Line one contentX Line two content F E V ?
```

`X` lands at the END of "Line one content" (col 17), not at col 5 (`LineX`) and not at col 0 (`XLine`). Per the action plan's mapping, this is the EOL-reset signature, which the plan flagged as a fourth-candidate territory. Probe output confirmed it is actually a refined Candidate B, not A or C.

## Confirmed root cause

**Mechanism:** the IconMenu's File-menu *dropdown items* are rendered as a panel that overlaps the buffer pane area. The buffer-pane TextField requests `:cursor_button` non-positionally via `request_input/2`, so it receives EVERY mouse click delivered to the viewport. When a click lands on a dropdown item whose viewport position falls inside the buffer pane's frame (e.g. clicking "New" under the File menu), `handle_buffer_backed_input/2` translates the click coordinates into a buffer (line, col) via `State.click_to_cursor/2` and dispatches `{:set_cursor, click_pos}` to `Buffer.Process` — overwriting whatever cursor the user had positioned with the keyboard.

**Probe trace** (relevant excerpts; full probe output captured during diagnosis run, probes since removed):

```
# 1. Cursor moved to col 5 by 4× right-arrow (works correctly)
DIAG_BUF_CAST buf_id=6a55a13a actions=[{:move_cursor, :right, 1}] → cursors=[col: 5]

# 2. spex calls create_new_buffer():
#    - first click is icon_menu_file at (1877.5, -17.5) — point_inside? = false (good)
#    - second click is icon_menu_file_new at (1805.0, 18.0) — point_inside? = TRUE
DIAG_TF_CLICK coords={1877.5, -17.5} inside?=false  frame_pin={0, 35} frame_size={2000, 1165}
DIAG_TF_CLICK coords={1805.0, 18.0}  inside?=true   frame_pin={0, 35} frame_size={2000, 1165}
DIAG_TF_CLICK_INSIDE → set_cursor={1, 17}
DIAG_BUF_CAST buf_id=6a55a13a actions=[set_cursor: {1, 17}] → cursors=[col: 17]
                                                        # ↑ buffer 1's cursor is now wrong

# 3. switch_to_buffer(1) — TextField re-init faithfully fetches cursor={1, 17} from buffer
DIAG_TAB_SELECTED tab_id=6a55a13a (current active="0614eda0")
DIAG_TF_INIT buf_id=6a55a13a initial_cursor_param={1, 17} buf_cursors=[col: 17] → cursor={1, 17}

# 4. Type "X" — inserted at col 17
DIAG_BUF_CAST buf_id=6a55a13a actions=[{:insert, "X", :at_cursor}] → cursors=[col: 18]
```

The `(1805, 18)` click is in the buffer pane's local frame coordinates (frame pinned at viewport y=35; click_y=18 means 18px below the top of the buffer pane — well inside). `click_to_cursor` then maps line=1, col=17 (clamped to end of "Line one content", which is 16 chars).

## Candidate analysis

- **Candidate A — TextField re-init drops cursor.** RULED OUT. Probe `DIAG_TF_INIT` shows the new TextField for buf 1 reads `buf_cursors=[col: 17]` from `Buffer.Process` and sets its display cursor to `{1, 17}`. TextField is faithful to whatever the buffer holds; the bug is upstream — the buffer already holds the wrong value.
- **Candidate B — Switch-away path mutates cursor.** CONFIRMED, with refinement: the mutator is not `:focus_lost`, it is the TextField's own click handler firing on a click that targets the IconMenu dropdown item but is delivered to the buffer-pane TextField because `request_input([:cursor_button, ...])` makes click delivery non-positional. The check `State.point_inside?/2` only filters by the buffer pane's frame, so dropdown items overlapping that frame slip through.
- **Candidate C — Cursor sync is one-way.** RULED OUT. Probes `DIAG_BUF_CAST actions=[{:move_cursor, :right, 1}]` (etc.) show every keyboard cursor edit reaches `Buffer.Process` via `handle_buffer_backed_input` and updates `state.cursors`. The arrow-keys / home / etc. all persist correctly; the buffer had col 5 at the moment between key-input completion and the spurious click.

## What the implementation task should fix

**File:** `/home/luke/workbench/flx/scenic-widget-contrib/lib/components/text_field/reducer.ex`
**Function:** `input_to_buffer_action/2` for `{:cursor_button, {:btn_left, 1, _, coords}}` (around line 697).

**Mechanism to change:** the click handler currently fires `{:set_cursor, click_pos}` whenever `State.point_inside?(state, coords)` returns true. That predicate only knows the TextField's own frame — it cannot tell whether some sibling component (an IconMenu dropdown, a modal, the file-nav sidebar, etc.) is rendered on top of that frame and is the real intended recipient of the click.

The fix should ensure the buffer-pane TextField does not steal clicks intended for sibling overlays. Two viable directions (the implementation task should pick one based on what the rest of the Scenic stack supports):

1. **Switch the cursor_button input registration from `request_input` (non-positional) to a positional `input: [:cursor_button]` opt on the buffer-pane primitive.** Per the user's CLAUDE.md Scenic doctrine, `request_input` is meant for non-positional inputs (keyboard, viewport resize); cursor clicks should be routed positionally via `:id`. Scenic's positional routing already accounts for sibling z-order, so dropdown clicks would be consumed by the IconMenu and never reach the TextField. This is the architecturally correct fix.
2. **Suppress click-driven `set_cursor` while a dropdown / modal is open.** Either gate the click handler on a "modal_open?" flag pushed down from the parent scene (RootScene already tracks IconMenu / search bar / file nav state), or have the IconMenu capture input while open. Smaller blast radius but does not address the underlying input-routing antipattern, so the next overlay added will hit the same bug.

Direction 1 is preferred — it removes the bug class, not just this instance. Note that text-drag selection (lines 778–814 of reducer.ex) also relies on `cursor_button` and `cursor_pos` delivery, so the migration needs to keep those paths working (text drag is currently triggered from within the same handler that fires `set_cursor`, so positional routing should naturally include both).

## Acceptance for the fix

When the spex at `04_view_settings_spex.exs:362` runs:
- Clicking "New" in the File dropdown must NOT dispatch `{:set_cursor, _}` to the previously-active buffer.
- After switching away and back, typing `X` must produce `LineX one content` (cursor preserved at col 5).
- The line-numbers / word-wrap toggle scenarios in the same file must still pass — they currently incidentally re-set the cursor via the same buggy path, but their assertions don't check cursor position, so removing the spurious set_cursor should leave them green.
