# Changelog

## 1.0.0 — 2026-09-10

Cut at ElixirConf. 0.8.2 was the release where every feature 1.0 needed
existed; the twenty-two pull requests since were the ones where using them for
a while found what still gave way. Wherever this is, this is 1.0.

- Search by filename (`Ctrl+P`): type part of a name, get the matching
  files, Enter opens one into the preview slot. The project tree is listed
  once when the popup opens, under the same excludes a project search
  honours, and every keystroke filters it in memory.
- Tab context menu: right-click a tab for Close Other Tabs, Close Tabs to
  the Right and Close All Tabs, with the unsaved-changes prompt where it
  applies.
- The cursor remembers the column it wanted. Moving up and down through a
  short line no longer loses your place on the next long one.
- Chrome zoom works from 50% to 400%: the sidebar and its path header move
  down under the taller tab bar instead of hiding behind it, tick boxes and
  the sliders grow with the text, the file tree grows a scrollbar when the
  zoom makes it taller than the window, and the zoom box keeps taking typed
  numbers after a zoom change instead of quietly typing them into the
  document. Editor text size now reaches 72pt.
- File navigator: shows every file, not a whitelist of extensions; the
  rename box is a real text field you can edit; a buffer whose file was
  deleted from disk is kept rather than thrown away, with the external
  change marker where you can actually see it.
- Search pane: paste works in its fields — a command chord in a direct-mode
  field no longer also types its letter.
- Escape lets go of the selection; double-click leaves the cursor at the
  start of the word; the buffer no longer scrolls sideways after a search.
- Housekeeping: the retired comprehensive spex was audited and what it alone
  covered was salvaged into current spex before it went; both coding agents
  get the same MCP servers from the repo; Claude Code's worktrees stay out
  of git.

## 0.8.2 — 2026-08-23

The product pass. Every feature 1.0 needs now exists; this release is the one
where they became findable, legible and consistent with each other.

- Added structural syntax highlighting. Keywords, names, strings and comments
  are marked by **weight**, *slant* and underline rather than colour, so the
  code reads the same for every kind of colour vision. Pure-Elixir Makeup
  lexers cover Elixir, Erlang, EEx, JSON, JavaScript, C and diff; Syntect
  fills the gaps (Markdown, shell, Python and many more) through the same
  registry.
- Added six themes — Alchemical Wedding in dark and light, Solarized in both,
  High Contrast, and Typewriter — each driving the editor *and* the whole
  interface. A light buffer inside a dark sidebar reads as broken rather than
  as a theme. Editor text size and interface scale adjust independently, and
  interface zoom now scales the chrome rather than only the frames it sits in.
- Added a project-wide search pane in the sidebar, with its own query,
  replacement and exclude-glob fields, results grouped by file, and a scope
  tree you tick directories in and out of. Results stream in as they are
  found rather than arriving all at once, and only the visible window is
  drawn — a 1100-row result set builds in 3.5ms instead of 79ms. Dismiss a
  match or a whole file before replacing, so Replace All is reviewable.
  Results open into one reusable preview tab.
- Added Go to Line (`Ctrl+G`), which clamps rather than refuses — `999999` is
  what people type when they mean "the end". Find Next moved to `F3`.
- Added code folding, matching-brace highlighting, and optional line and
  column guides.
- Added a choice of which key means "command", for people on a Mac, and
  settings that can be saved as defaults.
- File navigator: drag-to-move now has spring-loaded folders, edge
  auto-scroll, a ghost label on the cursor, themed drop colours, and
  drop-on-empty-space meaning the project root. Fixed the tree losing its
  expansion twice per file operation — a status toast put the root scene on
  its z-order rebuild path, and that path deleted the navigator outright.
- Tab bar: drag-to-reorder now shows a drop line anchored to the dragged
  tab's slot, with a 5px threshold so ordinary clicks don't flash it.
- Menus: one dropdown component now draws both the menu bar and the search
  pane's settings. Dropdowns scroll with a bar you can see and drag, fit
  inside any window size, close on Escape and on scrolling elsewhere, and
  nothing that redraws underneath one lands on top of it.
- Every feature is reachable from the menu bar, every control has a tooltip,
  and every shortcut is listed in Help → Keyboard Shortcuts.
- Cursor movement and clicks are wrap-aware, so word wrap no longer strands
  the end of a document out of reach.
- `scripts/run_demo` plays the whole feature set, narrated by the editor into
  its own buffer. It asserts as it goes — a demo that plays through while the
  feature underneath is broken would be worse than no demo at all.

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
