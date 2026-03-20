# Quillex - GEdit Clone Roadmap

A comprehensive breakdown of current functionality vs target functionality for a full GEdit-style text editor.

---

## Current State (What Works)

### UI Components
- [x] **Tab Bar** - Shows open buffers as tabs, clickable to switch
- [x] **Icon Menu** - Right-aligned toolbar with F/E/V/? dropdown menus
- [x] **Text Field** - Multi-line text editing with line numbers
- [x] **Window Resize** - Handles viewport resize events
- [x] **File Navigator** - Sidebar file browser panel (toggle via View menu)

### Core Editing
- [x] Basic text input (typing characters)
- [x] Cursor movement (arrow keys, Home/End)
- [x] Backspace/Delete
- [x] Enter for new lines
- [x] Line numbers display
- [x] Cursor blinking
- [x] Text selection (Shift+arrows)
- [x] Copy/Cut/Paste (Ctrl+C/X/V)
- [x] Undo/Redo (Ctrl+U/R)
- [x] Word wrap toggle
- [x] Find/Search (Ctrl+F) with Find Next (Ctrl+G) / Find Prev

### Buffer Management
- [x] Multiple buffers in memory (BufferManager)
- [x] Create new buffer (via File menu)
- [x] Switch between buffers (via tab clicks)
- [x] Buffer content persistence when switching tabs
- [x] Auto-generated buffer names ("unnamed-1", "unnamed-2", etc.)
- [x] Close tab functionality
- [x] Dirty/unsaved indicator (" *" on tab label)

### File Operations
- [x] Open file (file picker dialog)
- [x] Save file (Ctrl+S)
- [x] Save As
- [x] File integrity verification (detect external modifications)

### Menu System
- [x] Dropdown menus open on click
- [x] Right-aligned dropdowns (extend leftward to stay in window)
- [x] Menu items are clickable
- [x] Menus close after selection
- [x] Keyboard shortcuts shown in menu labels

---

## Known Bugs / Issues

### Critical
- [x] ~~**Tab switching may lose cursor position**~~ — FIXED (cursor preserved on tab switch)
- [x] ~~**No dirty/unsaved indicator**~~ — FIXED (" *" appended to tab label)
- [x] ~~**Close tab button doesn't work**~~ — FIXED (tab close implemented)

### UI/UX
- [ ] **Menu doesn't close on outside click** - menus stay open
- [x] ~~**No keyboard shortcuts**~~ — PARTIAL: Ctrl+S (save), Ctrl+F (find), Ctrl+U (undo), Ctrl+R (redo), Ctrl+G (find next) work
- [ ] **Tab overflow** - many tabs don't scroll/handle overflow well
- [ ] **No focus indication** - hard to tell which component has focus

### Text Editing
- [x] ~~**No text selection**~~ — FIXED (Shift+arrows, Select All)
- [x] ~~**No copy/paste**~~ — FIXED (Ctrl+C/X/V)
- [x] ~~**No undo/redo**~~ — FIXED (Ctrl+U/R)
- [x] ~~**No word wrap**~~ — FIXED (toggle in View menu)
- [x] ~~**No find/replace**~~ — DONE: Find (Ctrl+F) and Replace (Ctrl+H) both work
- [ ] **No syntax highlighting** - all text is same color

---

## Target Functionality (GEdit Feature Parity)

### File Operations
- [x] **New File** (Ctrl+N) - Create empty buffer
- [x] **Open File** (Ctrl+O) - File picker dialog, load file content
- [x] **Save** (Ctrl+S) - Save to current path (prompt if new)
- [x] **Save As** (Ctrl+Shift+S) - Save to new path
- [x] **Close Tab** (Ctrl+W) - Close buffer (prompt if unsaved)
- [x] **File Verification** (File menu → Verify File; no keyboard shortcut) - Check if file modified on disk
- [ ] **Recent Files** - List of recently opened files
- [ ] **File changed on disk detection** - Prompt to reload

### Edit Operations
- [x] **Undo** (Ctrl+U) - Undo last change
- [x] **Redo** (Ctrl+R) - Redo undone change
- [x] **Cut** (Ctrl+X) - Cut selection to clipboard
- [x] **Copy** (Ctrl+C) - Copy selection to clipboard
- [x] **Paste** (Ctrl+V) - Paste from clipboard
- [x] **Select All** (Ctrl+A) - Select entire document
- [x] **Delete Line** (Ctrl+D) - Delete current line
- [ ] **Duplicate Line** (Ctrl+Shift+D) - Duplicate current line
- [ ] **Move Line Up/Down** (Alt+Up/Down) - Reorder lines

### Text Selection
- [ ] **Click to position cursor** - Mouse click places cursor
- [ ] **Click and drag to select** - Mouse drag selects text
- [ ] **Double-click to select word** - Word selection
- [ ] **Triple-click to select line** - Line selection
- [x] **Shift+Arrow selection** - Keyboard text selection
- [ ] **Shift+Click selection** - Extend selection with mouse
- [ ] **Ctrl+Shift+Arrow** - Select by word

### Navigation
- [ ] **Go to Line** (Ctrl+G) - Jump to specific line number (Ctrl+G currently mapped to Find Next)
- [x] **Home/End** - Go to start/end of line
- [x] **Ctrl+Home/End** - Go to start/end of document
- [ ] **Page Up/Down** - Scroll by page
- [ ] **Ctrl+Left/Right** - Move by word
- [x] **Scroll with mouse wheel** - Vertical scrolling
- [x] **Horizontal scroll** - For long lines (if no word wrap)

### Find & Replace
- [x] **Find** (Ctrl+F) - Search bar with highlighting
- [x] **Find Next/Previous** (Ctrl+G) - Navigate matches
- [x] **Replace** (Ctrl+H) - Find and replace dialog
- [x] **Replace All** - Replace all occurrences
- [ ] **Case sensitive toggle** - Match case option
- [ ] **Regex search** - Regular expression support
- [ ] **Highlight all matches** - Visual indication of matches

### View Options
- [x] **Toggle Line Numbers** - Show/hide line numbers
- [x] **Toggle Word Wrap** - Soft wrap long lines
- [ ] **Toggle Minimap** - Code overview sidebar
- [x] **Toggle Sidebar** - File browser panel
- [ ] **Zoom In/Out** (Ctrl++/-) - Adjust font size
- [ ] **Full Screen** (F11) - Full screen mode
- [ ] **Status Bar** - Show line:column, encoding, file type

### Tab Management
- [x] **New Tab** (Ctrl+T) - New empty tab
- [x] **Close Tab** (Ctrl+W) - Close current tab
- [ ] **Close All Tabs** - Close all open tabs
- [ ] **Tab reordering** - Drag tabs to reorder
- [ ] **Tab overflow menu** - Dropdown for many tabs
- [ ] **Middle-click to close** - Mouse button tab close
- [x] **Modified indicator** - Asterisk on unsaved tabs (" *" suffix)

### Syntax & Appearance
- [ ] **Syntax highlighting** - Language-aware coloring
- [ ] **Theme support** - Light/dark themes
- [ ] **Current line highlight** - Highlight active line
- [ ] **Matching bracket highlight** - Show matching (){}[]
- [ ] **Indent guides** - Vertical lines for indentation
- [ ] **Whitespace visualization** - Show tabs/spaces optionally

### Advanced Features
- [ ] **Auto-indent** - Match indentation on new line
- [ ] **Auto-save** - Periodic background saves
- [ ] **Session restore** - Remember open tabs on restart
- [ ] **Multiple cursors** - Edit multiple locations at once
- [ ] **Code folding** - Collapse/expand blocks
- [ ] **Spell checking** - Underline misspelled words
- [ ] **Print** (Ctrl+P) - Print document

---

## Implementation Priority

### Phase 1: Core Stability (Must Have) — COMPLETED
1. ~~Fix tab close functionality~~ ✓
2. ~~Implement text selection (mouse + keyboard)~~ ✓ (keyboard done, mouse pending)
3. ~~Implement copy/paste (system clipboard)~~ ✓
4. ~~Implement undo/redo~~ ✓
5. ~~Add keyboard shortcuts for common operations~~ ✓ (Ctrl+S/F/U/R/G)
6. ~~Dirty/unsaved buffer indicator~~ ✓

### Phase 2: File Operations (Must Have) — MOSTLY COMPLETE
1. ~~Open file dialog~~ ✓
2. ~~Save file~~ ✓
3. ~~Save As dialog~~ ✓
4. Prompt on close unsaved — not yet

### Phase 3: Navigation & Search (Should Have) — PARTIALLY COMPLETE
1. ~~Find (Ctrl+F) with highlighting~~ ✓
2. ~~Replace (Ctrl+H) with Replace All~~ ✓
3. Go to line — not yet
4. Word-wise cursor movement — not yet
5. Page up/down — not yet

### Phase 4: Polish (Nice to Have)
1. Syntax highlighting (at least for Elixir)
2. Theme support
3. Status bar
4. Recent files
5. Session restore

---

## Architecture Notes

### Current Component Structure
```
QuillEx.RootScene
├── TabBar (ScenicWidgets.TabBar)
│   └── Sends {:tab_selected, id}, {:tab_closed, id}
├── IconMenu (ScenicWidgets.IconMenu)
│   └── Sends {:menu_item_clicked, item_id}
├── FileNavigator (ScenicWidgets.FileNavigator)
│   └── Sidebar file browser, toggle via View menu
└── TextField (ScenicWidgets.TextField)
    └── Handles direct input, stores lines internally
```

### Buffer Backend
```
Quillex.Buffer.BufferManager
├── new_buffer/0 - Create new buffer
├── list_buffers/0 - Get all buffer refs
└── call_buffer/2 - Send actions to buffer process

Quillex.Buffer.Process
├── Holds buffer state (lines, cursor, undo/redo stacks, etc.)
└── Handles {:action, [...]} messages
```

### Event Flow
1. User clicks menu item
2. IconMenu sends `{:menu_item_clicked, "new"}` to parent
3. RootScene `handle_event` receives it
4. Dispatches `{:action, :new_buffer}`
5. Reducer calls BufferManager.new_buffer()
6. BufferManager broadcasts `:new_buffer_opened`
7. RootScene updates state, re-renders graph
8. TabBar shows new tab, TextField shows empty buffer

---

## Testing Strategy (Spex)

### Unit Tests
- [x] Buffer state management (BufState.new, defaults) — `test/buffers/buf_state_test.exs`
- [x] Cursor selection logic — `test/reducers/buffer_reducer_cursor_selection_test.exs`
- [x] Dirty indicator tracking — `test/reducers/buffer_reducer_dirty_test.exs`
- [x] Buffer API tests — `test/api/buffer_api_tests.exs`
- [ ] Undo/redo stack operations
- [ ] Text manipulation (insert, delete)

### Integration Tests (Spex)
- [x] App launch — `01_app_launch_spex.exs`
- [x] Basic text editing — `02_basic_text_editing_spex.exs`
- [x] Buffer management — `03_buffer_management_spex.exs`
- [x] Tab handling — `04_tab_handling_spex.exs`
- [x] View settings — `04_view_settings_spex.exs`
- [x] Undo/redo — `05_undo_redo_spex.exs`
- [x] Find — `06_find_spex.exs`
- [x] Integration v1 — `07_integration_v1_spex.exs`
- [x] Property tests — `08_property_tests_spex.exs`
- [x] File operations — `09_file_operations_spex.exs`
- [x] File navigator — `10_file_navigator_spex.exs`
- [x] Run verification (file integrity check) — `11_run_verification_spex.exs`
- [x] Find & Replace (Ctrl+H) — `12_replace_spex.exs`
- [x] Menu close on outside click — `13_menu_close_outside_click_spex.exs`
- [x] Keyboard shortcuts (Ctrl+N/O/W/S/etc.) — `14_keyboard_shortcuts_spex.exs`

### Visual/E2E Tests (via ScenicMCP)
- [x] Menu opens on click
- [x] Menu closes on selection
- [x] Tab selection highlights correctly
- [ ] Cursor visible and positioned correctly

---

## Notes

- GEdit is GTK-based, Quillex is Scenic-based - some features may need reimagining
- System clipboard integration requires platform-specific code
- File dialogs need custom implementation (Scenic has no native dialogs)
- Consider Wayland/X11 differences for Linux clipboard
- Tab width is configurable (2/3/4/8 spaces) via View menu
