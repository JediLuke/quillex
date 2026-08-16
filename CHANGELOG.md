# Changelog

## Unreleased

- Added project-wide find and replace. Ctrl+Shift+F (Edit → Find in Project)
  opens the same top-right find popup plus a results pane in the sidebar slot;
  the popup's query drives both the active buffer and the project search, so
  the two never disagree. Results are grouped by file with `line:col` rows
  that open the file at the match; a SCOPE tree ticks directories in and out;
  Ctrl+Shift+H / "All" replaces across every in-scope file — open buffers are
  edited in place (undoable, unsaved), everything else is rewritten on disk.
  Search runs off-process through a `Quillex.Search.Backend` behaviour:
  ripgrep when installed, a pure-Elixir walk otherwise
  (`config :quillex, search_backend: :auto | :ripgrep | :elixir`).
- Fixed find/replace on large wrapped documents freezing for seconds per
  keystroke: every match in the document was a primitive, each re-wrapping
  its line, and the whole document was re-wrapped twice per edit. Match
  and selection highlights are now virtualised to the render window and
  positioned through the cached display projection; wrapping is memoised per
  line, so an edit re-wraps only what it touched. Spinoza with word wrap:
  10s → ~40ms per keystroke in the search box.
- Fixed search columns being byte offsets: after any multibyte character
  (an em dash) highlights sat two characters right of the match and Replace
  would have spliced the wrong text. Search now uses caseless regex scanning
  with grapheme columns (7× faster too).
- Find UX: the current match is revealed centred when it is off screen; find
  starts at the match under or after the cursor; Replace advances past the
  replacement (a case-insensitive "the" → "THE" no longer re-hits itself);
  navigating a wrapped document no longer scrolls sideways; a jump to a far
  match no longer leaves rows unrendered; Ctrl+H works while the search bar
  has focus; the match counter fits four digits.

- Added supervised external-file synchronization in every runtime mode. Clean
  open buffers reload automatically when their canonical files change, including
  inactive tabs, and the status bar reports the reload.
- External changes never overwrite dirty buffers. Modified or deleted backing
  files set durable conflict metadata (and a tab `!` marker), while Quillex's
  own saves are recognized without producing a false conflict.
- External reload now uses an atomic buffer-process cleanliness check, so a
  keystroke racing the disk watcher cannot be overwritten.

## 0.7.4 — 2026-08-03

- Fixed every shifted character being discarded — capitals and all shifted
  punctuation. TextField rejected any codepoint carrying modifiers, but Shift
  is a text modifier the driver has already applied ("A" arrives as
  {"A", [:shift]}). Only :ctrl and :meta disqualify a codepoint now; :alt is
  allowed because macOS Option composes characters.
- Added `Probes.send_codepoint/2`. The harness could not send a shifted
  keystroke at all — `send_text` always used empty modifiers — which is why a
  green suite never noticed.
- Added `28_character_input_spex.exs`, verified to fail against the bug.
- Fixed the file navigator never scrolling, on either axis. Scroll is
  positional input and Scenic hit-tests it only against primitives that ask for
  `:cursor_scroll`; no SideNav primitive did, and the root scene's `put_child`
  forwarding never arrived. SideNav now requests scroll itself and
  bounds-checks the pointer, like TextField. Horizontal was broken twice over —
  the reducer also discarded `dx`.
- Fixed "Ln X, Col Y" freezing at the initial position. Buffers carried
  `cursors: [cursor]` until multi-cursor was removed in 0.7.3; the label still
  matched the list shape, and a catch-all clause quietly re-displayed the last
  known value. That clause is gone — an unrecognised snapshot now crashes.
- Sized the file navigator's font against the editor's text size but
  deliberately smaller (`SideNavThemes.for_editor/1`); it previously rendered
  at exactly the buffer's size.
- Centred the cursor-position label so its left and right padding match, and
  widened its frame to fit five-digit line numbers.
- Fixed toolbar icon hover recolouring only part of each glyph, and filling
  outline icons solid instead of recolouring their strokes.
- Added `25_side_nav_scroll_spex.exs`. A fully green suite missed all of the
  above because every existing spex drove the buffer, never the sidebar.
- Made `bin/qlx` and `scripts/run_spex.sh` portable off GNU coreutils and X11,
  ahead of trying this on macOS.

## 0.7.3 — 2026-08-02

- Added explicit buffer Ref/Snapshot contracts, canonical path identity,
  duplicate-open activation, safe save/save-as, and enforced read-only buffers.
- Added standalone, embedded, and headless modes plus deferred dirty-close
  protection.
- Fixed nested input scissors, modified-codepoint leakage, undo/redo, scrollbar
  math, tab overflow, active file navigation, and per-buffer scroll restoration.
- Added reusable scroll, indentation-fold, and typed menu models.
- Added vector toolbar icons, a shared modal shell, and a FilePicker backed by
  the normal single-line TextField.
- Split pure editing, navigation, selection, search, position, and history
  logic behind the public Ref/Snapshot API.
- Made performance measurement execute work exactly once and expanded focused
  multi-repository regression coverage.
