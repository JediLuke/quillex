# The Spex Audit — mining `test/old_spex/` before it goes

*2026-08-23, at 0.8.2. Written against `main` (3dd9e32), before PR #16 deletes
`test/old_spex/`.*

`test/spex/quillex/` is meant to become the single place that defines,
exhaustively, what Quillex is and does. Before the 57 retired files in
`test/old_spex/` (~10,900 lines) are archived away, this document mines them:
every behaviour they ever asserted, whether the current suite still asserts
it, and — the more valuable half — the behaviours the app really has that
*nobody* has ever written down. It ends with a prioritised list of what to add
to make the numbered suite the complete specification, and a short list of
things that look like real bugs.

Method: all 56 files were read in full (assertions, not scenario titles);
`comprehensive_text_editing_spex.exs` is excluded here because it is being
cross-checked separately on `test/comprehensive-editing-coverage`. Coverage
claims below name the exact covering test. Two facts established by that
parallel work are taken as given: the selection-cancel bug is fixed and
covered by `test/reducers/buffer_reducer_cursor_selection_test.exs`, and the
sticky/desired-column feature has just been implemented on
`feature/sticky-cursor-column`.

---

## 1. What the old suite was

Three strata, and it matters which one a file belongs to:

1. **Real feature suites** — `text_editing_spex.exs` (1,280 lines, the
   original "notepad.exe functionality" suite), `cursor_movement_boundaries`,
   `cursor_position_after_paste`, `multiline_paste_cursor_position`,
   `semantic_text_editing`, `hello_world`. These asserted behaviour and are
   the ancestors of today's `02`, `05`, `56` et al.
2. **Bug reproductions** — `minimal_vertical_bug`, `debug_selection_bug`,
   `verify_backspace_fix`, `isolated_selection_edge_case`,
   `verify_cursor_column_fix`. `DEBUG_FILES_SUMMARY.md` records which were
   kept deliberately as live-bug reproductions; §4 settles each one.
3. **Debug scaffolding** — thirty-odd `debug_*`/`diagnose_*`/`trace_*` files
   from the 2025 era when *the test harness itself* was the thing being
   debugged (text arriving truncated, select-all racing the renderer, the
   ScriptInspector returning lines in the wrong order). Their `assert`s are
   incidental; their real content was `IO.puts`. The lessons they taught —
   async settling, `wait_for_text_to_appear`, sorting script-table text by
   (y, x) — are already institutionalised in `Quillex.TestHelpers` and in the
   discipline of the numbered suite.

Three files never ran at all: `real_mcp_spex.exs`, `actual_scenic_mcp_spex.exs`
and `claude_bridge_spex.exs` are **commented out top to bottom** (they were
simulations of MCP tooling that predated the real thing). A fourth,
`slow_visual_text_editing_spex.exs`, **cannot compile** — it contains
`if ... then` and `elsif`, which are not Elixir. Nothing in any of the four is
worth carrying forward.

## 2. The behaviour ledger

Every distinct behaviour the 56 files asserted, deduplicated (the same
select-all assertion appears in eleven files), with where it lives now.
"Covered" names the exact test; unit tests count — a reducer test is a better
home than a spex for backend behaviour.

| # | Behaviour asserted by old_spex | Status | Where |
|---|---|---|---|
| 1 | App launches; viewport `:main_viewport`; initial buffer empty, cursor visible | Covered | `01_app_launch_spex.exs` |
| 2 | Typing renders exactly the typed characters, spaces included, immediately after boot (auto-focus, no click needed) | Covered | `50_boot_and_typing`, `02_basic_text_editing`, `28_character_input`, `18_focus_indication` |
| 3 | Enter splits/creates lines; typing continues on the new line; backspace at line start joins | Covered | `02_basic_text_editing_spex.exs` |
| 4 | Backspace deletes before cursor; Delete deletes at cursor; both merge lines at boundaries | Covered | `02`; reducer `buffer_reducer_test.exs` (`{:delete, :before_cursor}` / `{:delete, :at_cursor}` describes, incl. line-merge and no-op-at-edge cases) |
| 5 | Backspace with an active selection deletes the whole selection, not one character | Covered | `buffer_reducer_test.exs` "with selection active, deletes the selected text instead of one character" (both delete directions) |
| 6 | Home/End go to line boundaries; Ctrl+Home/Ctrl+End to document boundaries, clearing selection | Covered | reducer `:line_start`/`:line_end`/`:doc_start`/`:doc_end` describes; used as primitives throughout the numbered spex |
| 7 | Shift+Arrow selects; typing replaces the selection; plain movement collapses it | Covered | `56_selection_and_mouse`, `30_clipboard`; `buffer_reducer_cursor_selection_test.exs`; `buffer_mutator_select_text_test.exs` |
| 8 | Shift+Down extends a selection across lines; typing replaces the multi-line span | Covered (unit) | `buffer_mutator_select_text_test.exs` "continuing selection with shift+right after shift+down"; reducer "deletes multi-line selection correctly", "payload insertion with active selection" |
| 9 | Expand-then-contract selection (Shift+Right ×2, Shift+Left ×2) cancels cleanly; typing inserts at the anchor | Covered | `buffer_reducer_cursor_selection_test.exs` "collapsing back onto the anchor clears the selection" — the bug `debug_selection_bug_spex.exs` was kept for is fixed |
| 10 | Ctrl+A selects all; then typing replaces the whole document; then Delete/Backspace/Ctrl+X empties it | Covered (unit) | reducer "select_all then insert replaces entire multi-/single-line buffer content", `{:delete, :at_cursor}`-with-selection, cut describes. GUI path exercised constantly as every old file's `clear_buffer_reliable()` |
| 11 | Select-all on an empty buffer is harmless | Covered | reducer "leaves empty buffer unchanged" |
| 12 | Ctrl+C/Ctrl+V duplicates the selection at the cursor; Ctrl+X/Ctrl+V moves it | Covered | `56_selection_and_mouse`, `30_clipboard`, `20_mouse_cut`; reducer copy/cut/paste describes incl. mouse-selection cut |
| 13 | **Cursor position after paste**: at the end of pasted text (single-line), at the end of the *last pasted line* (multi-line) — the bug `multiline_paste_cursor_position_spex.exs` was kept for | **Was a gap — closed by this audit** | new `test/reducers/buffer_reducer_paste_cursor_test.exs` (8 tests, each verified to fail against the historical bug shape) |
| 14 | Vertical movement clamps the column to a shorter line's end (down and up) | Covered | reducer "moving up to a shorter line clamps the column"; sticky-column work on `feature/sticky-cursor-column` extends this |
| 15 | Ghost cursor / column memory across a short line | In flight | `feature/sticky-cursor-column` (feature was missing; now implemented there). Note: the old `cursor_movement_boundaries_spex.exs` asserted the column survives *typing a marker* on the short line, which is stronger than the convention (typing normally resets the desired column) — worth a deliberate decision when that branch's tests land |
| 16 | Document boundaries are hard: Up on line 1, Down on the last line, Left at doc start, Right at doc end are no-ops | Covered | reducer clamp describes; `08_property_tests` "Random cursor movements maintain bounds"; `17_page_navigation` clamping |
| 17 | Left at the start of a *middle* line moves to the previous line's end | **Changed — see §5.1** | Current code clamps instead (`editing.ex` `move_cursor_with_bounds/4`); current reducer test *pins the clamp* ("moving left clamps at column 1") |
| 18 | Page Up/Down move by a page, clamp at edges, clear selection | Covered | `17_page_navigation_spex.exs`; reducer page describes |
| 19 | Trailing space at end of a typed line is preserved and rendered | Minor gap | Nothing asserts a trailing space survives render. Low value alone; the character-input spex (28) is the natural home if wanted |
| 20 | Buffer state and rendered state agree; semantic layer exposes buffer content/cursor | Covered | the entire numbered suite's method (`ScriptInspector`, `SemanticHelpers`); `04_view_settings` "Cursor position is exposed via semantic layer" |
| 21 | Vertical-cursor "line reordering" bug (`minimal_vertical_bug_spex.exs`, kept as live repro) | Obsolete | Not reproducible against current code (established by the parallel cross-check). The scenario shape (up, type, assert order) lives on in `02` and the comprehensive-editing work |
| 22 | "Insert mode" via `i` (in `debug_typing.exs`) | Obsolete | Vim-era fossil; there are no modes |
| 23 | Old internal APIs (`BufferManager.call_buffer(ref, {:action, …})`, `get_live_buffer`, `:buffer_pane` child, `QuillEx.RootScene` module name) | Obsolete | Replaced by `Quillex.Buffer` Ref/Snapshot contract (`buffer_contract_test.exs`) and the PaneStore architecture |
| 24 | Scene-hierarchy integrity checks (parent/child bidirectional, depths) in `text_editing_spex` and `semantic_text_editing_spex` | Obsolete as tests | This was harness self-validation. The property survives structurally: the semantic layer *is* the suite's read path, so corruption fails everything |

### Per-file disposition

For the record, so PR #16 can delete with a clean conscience:

- **Mined, behaviour extracted above** — `text_editing`, `hello_world`,
  `minimal_text_editing`, `fixed_text_editing`, `semantic_text_editing`,
  `textfield_typing_test`, `cursor_movement_boundaries`,
  `cursor_column_adjustment`, `simple_cursor_column_test`,
  `verify_cursor_column_fix`, `verify_backspace_fix`, `isolated_enter_key`,
  `isolated_select_all`, `isolated_selection_edge_case`,
  `minimal_shift_arrow_test`, `minimal_multiline_selection`,
  `debug_shift_arrow_selection`, `debug_selection_bug`,
  `cursor_position_after_paste`, `multiline_paste_cursor_position`,
  `test_buffer_clearing`, `test_with_buffer_assertions`,
  `minimal_vertical_bug`, `debug_space_character`.
- **Debug scaffolding, no behaviour beyond the ledger** — every other
  `debug_*`, `diagnose_*`, `trace_*` file, `profile_operations.exs`,
  `check_children`, `final_debug`, `buffer_state_check`,
  `inspect_initial_state`, `minimal_debug`, `direct_input_test`,
  `sexy_spex_timeout_patch.ex`, `cleanup_debug_spex_files.sh`.
- **Never ran** — `real_mcp_spex.exs`, `actual_scenic_mcp_spex.exs`,
  `claude_bridge_spex.exs` (fully commented out),
  `slow_visual_text_editing_spex.exs` (invalid Elixir: `if … then`, `elsif`).
- **Handled elsewhere** — `comprehensive_text_editing_spex.exs`
  (`test/comprehensive-editing-coverage`).

The `DEBUG_FILES_SUMMARY.md` scorecard, settled: selection-cancel — fixed and
unit-covered; vertical reordering — not reproducible; multi-line paste cursor
— correct in the code but unasserted until now (ledger #13).

## 3. The unspoken specification

Behaviours that are real, that a user would notice changing, and that were
never written down. Each one names the code that decides it and says whether
anything asserts it. These came from walking the feature boundaries — the
places where two features meet and somebody once made a choice.

### 3.1 Project search's Next crosses buffers — the flagship example

**Believed behaviour**: with project-wide results showing, Next advances
through the *flattened, cross-file* match list; when the next match is in a
different file, the editor switches to that file (into the reusable preview
tab) and puts the cursor on the match.

**The code**: `ProjectSearchStore.select_relative/2`
(`lib/gui/radix_cache/project_search_store.ex:217`) walks
`flat_matches(state.view.files)` — all files, flattened — and RootScene's
`{:search_pane, :next_match}` handler (`lib/gui/scenes/root/qlx_root_scene.ex:1945`)
feeds the selection to `open_selected_preview`, which opens whatever file the
match is in.

**What asserts it**: partially. `41_project_search_spex.exs` ("next and
previous walk the flattened result set") asserts after Next that
`root_state().active_buf.path == path` *and* the cursor is at `{line, col}` —
but its walk is 1→2→1, and matches 1 and 2 are both in `lib/alpha.ex` (the
fixture puts four matches there before `beta.txt`'s two). **The file-boundary
hop itself is never exercised in the GUI.** At the store level,
`project_search_test.exs` "project navigation selects exact matches and
wraps" does cross files and wrap around. So the answer to "is it true?" is
yes; the answer to "does anything prove the buffer actually switches when the
boundary is crossed?" is no.

### 3.2 The find bar does not follow you across tabs

**Believed behaviour**: buffer search state (`search_matches`,
`search_current_index`) lives in each `BufState`. The find bar's query is
dispatched to the pane only when the query or its options change
(`qlx_root_scene.ex:1013` and `:1032` are the only `perform_search` call
sites). Nothing in the buffer-switch path re-runs the search. So: open Find,
type a query, get "3 of 17", click another tab — the bar still shows the old
query and count, and the new buffer shows its own (usually empty) match set.
Typing in the bar re-searches the *now-active* buffer.

**What asserts it**: nothing. This is a real design decision at the
search/buffer-switch boundary (contrast the project pane, which by design
follows the active document — `ProjectSearchStore` subscribes to
`:radix_pane_main`, `ARCHITECTURE.md` store inventory). Whether the *bar's
stale count* is the wanted behaviour deserves a deliberate yes/no; either way
it should be written down as a spex.

### 3.3 Closing the active tab activates its right neighbour

**Believed behaviour**: close the active tab and the tab that was immediately
to its right becomes active; at the end of the strip it falls back left. The
comment in `close_state/2` says why: "Keep the user's place in the tab strip"
(`lib/buffers/exec/buffer_manager.ex:262-267`).

**What asserts it**: fully covered —
`test/gui/scenes/qlx_root_scene_test.exs` "closing the active buffer selects
its right neighbour, then its left neighbour". Recorded here because it is
exactly the kind of decision this document exists to surface, and it turned
out to be one of the well-asserted ones.

### 3.4 Any edit that changes the line count unfolds everything

**Believed behaviour**: folds survive edits that keep the line count constant
and are *all discarded* the moment a line is added or removed —
`Folding.reconcile_after_edit/3` in scenic-widget-contrib
(`text_field/folding.ex:56`): `if length(old) == length(new), do: folds, else:
MapSet.new()`. Also: jumping into a folded region (goto-line, search) expands
the fold that hides the target (`expand_to_line/3`, `folding.ex:50`).

**What asserts it**: nothing in Quillex. `35_folding_spex.exs` covers
toggling, fold-to-level and the gutter menu, never the folding × editing
boundary. The discard-on-count-change rule is a blunt but defensible choice —
it should be either asserted or improved, not left ambient. (The code is in
contrib, so the *assertion* belongs in a Quillex spex; a smarter reconcile
would be a contrib change.)

### 3.5 Untitled buffer names are reused

`generate_unique_buffer_name/1` (`buffer_manager.ex:341`) yields "untitled",
"untitled-2", "untitled-3"… taking the first number not currently in use — so
closing "untitled-2" means the next new buffer *becomes* "untitled-2" again.
`03_buffer_management` asserts uniqueness only, not the numbering or reuse.
Harmless, user-visible, unwritten.

### 3.6 Opening a missing path creates a buffer, not a file

`qlx notes.txt` for a file that doesn't exist creates a **clean** empty buffer
bound to that path (`FileAPI.do_open_new`, `lib/api/file_api.ex`, the
`{:error, :enoent}` branch, returning `created: true`); the disk file appears
on first save, not on open. The README's "creating it, if it doesn't exist
yet" is loose about this. **Now asserted** by the new
`test/api/file_api_open_test.exs`, along with byte-for-byte open→save
round-trip fidelity (trailing newline and trailing spaces preserved, no
newline appended to files that lack one — `Buffer.save` is
`Enum.join(lines, "\n")`, `lib/api/buffer_api.ex:96`) and the two-layer
duplicate-open guard (`file_api.ex:45` and `buffer_manager.ex:115`; breaking
either alone is invisible, which the audit verified by breaking both).

### 3.7 Behaviours checked and found well-asserted

Worth listing so nobody re-audits them: find starts at the match under or
after the cursor and wraps (`buffers/search_test.exs` "set/2" describe);
replace advances past its own replacement (same file); search options are
per-buffer and survive edits; grapheme (not byte) columns after multibyte
text; case/regex modes and their composition (`find_bar_modes_test.exs`,
`51_find_options`); external file sync in all its cases — clean reload
active/inactive, dirty never overwritten, delete marks, save-as retargets,
own-save absorbed (`external_file_sync_test.exs`, `29_external_file_sync`);
dirty tracking across undo to and past the saved baseline
(`buffer_reducer_test.exs` History describes); the last buffer cannot be
closed (`03`, `14`, `close_state` unit tests); unsaved-close prompt paths
(`16`); the overlay keyboard gate (`18`, `19`, `40`, `48`); word navigation
(`15`, `buffer_utils_test.exs`); go-to-line clamping (`43`); wrapped-cursor
movement (`44`); themes reaching every surface (`45`); menu discoverability
and shortcut registry audit (`47`); Replace All reviewability — dismissals
excluded from replace, cleared on query change not on re-run
(`project_search_test.exs`, `41`).

## 4. What to add — prioritised

Ordered by the value of the assertion, not the ease. Effort is honest.

1. **Cross-buffer Find Next spex** (§3.1). Extend the walk in a *new* spex
   file past the alpha.ex/beta.txt boundary: from match 4, one Next must
   switch `active_buf.path` to beta.txt with the cursor on its first match,
   and the preview-tab behaviour must hold. The fixture and semantic-click
   machinery in 41 is the template. *Effort: half a day; the helpers can't be
   imported across spex files, so some duplication.*
2. **Find bar × tab switch spex** (§3.2) — after the owner decides whether
   the stale count is the spec. Open Find in buffer A with matches, switch to
   B, assert: bar text, match count, highlights in B, and what typing in the
   bar then searches. *Effort: small once decided; the decision is the work.*
3. **Folding × editing spex** (§3.4). Fold a region; edit without changing
   line count (folds survive); insert a line (folds all clear); Ctrl+G into a
   hidden line (that fold expands). *Effort: small — 35's helpers show how to
   drive the gutter.*
4. **Line-boundary arrows** (§5.1). Decide wrap vs clamp. Then it is a
   two-line reducer test either way — but today the suite *pins the clamp*,
   so deciding "wrap" means changing contrib + reducer tests together.
   *Effort: decision small; wrap implementation touches contrib's TextField.*
5. **CRLF policy** (§5.2). Decide, then unit tests on `TextFile`/`FileAPI`.
   *Effort: tests trivial; normalising-on-open with preserve-on-save is a
   real (small) feature.*
6. **Status-message timer race** — the `make_ref()`-stamped clear timer
   (`view_store.ex:105-118`) is sixteen lines of correctness nothing asserts.
   A unit test can send a stale `{:clear_status, old_ref}` directly. *Effort:
   tiny.*
7. **Sticky column** — arrives with `feature/sticky-cursor-column`; fold the
   old ghost-cursor scenarios' stronger claims (ledger #15) into that
   branch's review rather than duplicating here.
8. **Trailing-space render assertion** (ledger #19) — one `and_` in 28 if
   ever touched. *Effort: trivial, value small.*
9. **`qlx` CLI end-to-end** — boot the release with a file argument, assert
   the buffer, close. The only behaviours with *no* automated coverage at any
   level are `bin/qlx`'s own (build-offer, stale warning, log redirection).
   *Effort: large; a release build in CI is its own project. Defer past 1.0.*

Added by this audit (both verified by breaking `lib/` and watching them fail,
then restoring it byte-identical):

- `test/reducers/buffer_reducer_paste_cursor_test.exs` — ledger #13, the one
  confirmed live gap from the kept bug-reproduction files.
- `test/api/file_api_open_test.exs` — §3.6: open-missing-path contract,
  round-trip byte fidelity, duplicate-open.

## 5. Findings that look like real bugs

Reported, deliberately not fixed — this audit changes nothing under `lib/`.

### 5.1 Left/Right arrows no longer cross line boundaries

`move_cursor_with_bounds/4` (`lib/buffers/core/editing.ex`, the `:left` and
`:right` cases) clamps at column 1 and at line-end respectively. In nearly
every editor, Left at the start of a line lands at the end of the previous
line, and Right at line-end lands at the start of the next. The old suite
**asserted the wrap** (`cursor_movement_boundaries_spex.exs`, "Cross-line
movement at boundaries": Left from the start of line 2 of `AAA/BBB/CCC` had
to type at `AAA*`), so the behaviour existed in the pre-TextField editor and
was lost in the migration. The current reducer test suite *pins the clamp*
("moving left clamps at column 1"), which makes this either an undocumented
regression that got enshrined, or a deliberate simplification nobody wrote
down. Either answer is fine; it should stop being ambient. If wrap is wanted,
the fix is in the reducer's `{:move_cursor, direction, x}` path and the two
pinning tests.

### 5.2 CRLF files are read verbatim, and editing them produces mixed endings

Every read path splits on `"\n"` only (`file_api.ex:78`,
`buffer_api.ex:130`, `buffer_supervisor.ex:15`); `TextFile.read/1` validates
UTF-8 and NUL but not `\r`. A Windows-authored file therefore loads with a
trailing `\r` on every line — invisible in the render but present in column
arithmetic, `line_end`, and search columns — and lines the user *adds* have
no `\r`, so a save produces mixed line endings. No test at any level mentions
`\r\n`. The cheapest honest policy is normalise-on-open (and either preserve
or declare LF-only on save); the current behaviour is the one nobody chose.

### 5.3 Settled non-bugs, for the record

The "vertical cursor line reordering" bug (`minimal_vertical_bug_spex.exs`)
does not reproduce. The "selection not cancelling" bug is fixed and
unit-covered. Multi-line paste positions the cursor correctly — the kept
reproduction was right that nothing asserted it, and that assertion now
exists.
