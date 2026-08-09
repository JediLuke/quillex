# Changelog

## Unreleased

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
