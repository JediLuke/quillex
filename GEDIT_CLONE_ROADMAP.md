# Quillex - GEdit Clone Roadmap

A comprehensive breakdown of current functionality vs target functionality for a full GEdit-style text editor.

---

## Current State (What Works)

### UI Components
- [x] **Tab Bar** - Shows open buffers as tabs, clickable to switch
- [x] **Icon Menu** - Right-aligned toolbar with F/E/V/? dropdown menus
- [x] **Text Field** - Multi-line text editing with line numbers
- [x] **Window Resize** - Handles viewport resize events

### Core Editing
- [x] Basic text input (typing characters)
- [x] Cursor movement (arrow keys)
- [x] Backspace/Delete
- [x] Enter for new lines
- [x] Line numbers display
- [x] Cursor blinking

### Buffer Management
- [x] Multiple buffers in memory (BufferManager)
- [x] Create new buffer (via File menu)
- [x] Switch between buffers (via tab clicks)
- [x] Buffer content persistence when switching tabs
- [x] Auto-generated buffer names ("unnamed-1", "unnamed-2", etc.)

### Menu System
- [x] Dropdown menus open on click
- [x] Right-aligned dropdowns (extend leftward to stay in window)
- [x] Menu items are clickable
- [x] Menus close after selection

---

## Known Bugs / Issues

### Critical
- [ ] **Tab switching may lose cursor position** - cursor resets to start
- [ ] **No dirty/unsaved indicator** - no way to know if buffer has unsaved changes
- [ ] **Close tab button doesn't work** - handler exists but not implemented

### UI/UX
- [ ] **Menu doesn't close on outside click** - menus stay open
- [ ] **No keyboard shortcuts** - Ctrl+N, Ctrl+S, etc. don't work
- [ ] **Tab overflow** - many tabs don't scroll/handle overflow well
- [ ] **No focus indication** - hard to tell which component has focus

### Text Editing
- [ ] **No text selection** - can't select text with mouse or shift+arrows
- [ ] **No copy/paste** - Ctrl+C/V don't work
- [ ] **No undo/redo** - Ctrl+Z doesn't work
- [ ] **No word wrap** - long lines extend off screen
- [ ] **No find/replace** - Ctrl+F doesn't work
- [ ] **No syntax highlighting** - all text is same color

---

## Target Functionality (GEdit Feature Parity)

### File Operations
- [ ] **New File** (Ctrl+N) - Create empty buffer
- [ ] **Open File** (Ctrl+O) - File picker dialog, load file content
- [ ] **Save** (Ctrl+S) - Save to current path (prompt if new)
- [ ] **Save As** (Ctrl+Shift+S) - Save to new path
- [ ] **Close Tab** (Ctrl+W) - Close buffer (prompt if unsaved)
- [ ] **Recent Files** - List of recently opened files
- [ ] **File changed on disk detection** - Prompt to reload

### Edit Operations
- [ ] **Undo** (Ctrl+Z) - Undo last change
- [ ] **Redo** (Ctrl+Shift+Z / Ctrl+Y) - Redo undone change
- [ ] **Cut** (Ctrl+X) - Cut selection to clipboard
- [ ] **Copy** (Ctrl+C) - Copy selection to clipboard
- [ ] **Paste** (Ctrl+V) - Paste from clipboard
- [ ] **Select All** (Ctrl+A) - Select entire document
- [ ] **Delete Line** (Ctrl+D) - Delete current line
- [ ] **Duplicate Line** (Ctrl+Shift+D) - Duplicate current line
- [ ] **Move Line Up/Down** (Alt+Up/Down) - Reorder lines

### Text Selection
- [ ] **Click to position cursor** - Mouse click places cursor
- [ ] **Click and drag to select** - Mouse drag selects text
- [ ] **Double-click to select word** - Word selection
- [ ] **Triple-click to select line** - Line selection
- [ ] **Shift+Arrow selection** - Keyboard text selection
- [ ] **Shift+Click selection** - Extend selection with mouse
- [ ] **Ctrl+Shift+Arrow** - Select by word

### Navigation
- [ ] **Go to Line** (Ctrl+G) - Jump to specific line number
- [ ] **Home/End** - Go to start/end of line
- [ ] **Ctrl+Home/End** - Go to start/end of document
- [ ] **Page Up/Down** - Scroll by page
- [ ] **Ctrl+Left/Right** - Move by word
- [ ] **Scroll with mouse wheel** - Vertical scrolling
- [ ] **Horizontal scroll** - For long lines (if no word wrap)

### Find & Replace
- [ ] **Find** (Ctrl+F) - Search bar with highlighting
- [ ] **Find Next/Previous** (F3/Shift+F3) - Navigate matches
- [ ] **Replace** (Ctrl+H) - Find and replace dialog
- [ ] **Replace All** - Replace all occurrences
- [ ] **Case sensitive toggle** - Match case option
- [ ] **Regex search** - Regular expression support
- [ ] **Highlight all matches** - Visual indication of matches

### View Options
- [ ] **Toggle Line Numbers** - Show/hide line numbers
- [ ] **Toggle Word Wrap** - Soft wrap long lines
- [ ] **Toggle Minimap** - Code overview sidebar
- [ ] **Toggle Sidebar** - File browser panel
- [ ] **Zoom In/Out** (Ctrl++/-) - Adjust font size
- [ ] **Full Screen** (F11) - Full screen mode
- [ ] **Status Bar** - Show line:column, encoding, file type

### Tab Management
- [ ] **New Tab** (Ctrl+T) - New empty tab
- [ ] **Close Tab** (Ctrl+W) - Close current tab
- [ ] **Close All Tabs** - Close all open tabs
- [ ] **Tab reordering** - Drag tabs to reorder
- [ ] **Tab overflow menu** - Dropdown for many tabs
- [ ] **Middle-click to close** - Mouse button tab close
- [ ] **Modified indicator** - Dot/asterisk on unsaved tabs

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

### Phase 1: Core Stability (Must Have)
1. Fix tab close functionality
2. Implement text selection (mouse + keyboard)
3. Implement copy/paste (system clipboard)
4. Implement undo/redo
5. Add keyboard shortcuts for common operations
6. Dirty/unsaved buffer indicator

### Phase 2: File Operations (Must Have)
1. Open file dialog
2. Save file
3. Save As dialog
4. Prompt on close unsaved

### Phase 3: Navigation & Search (Should Have)
1. Find (Ctrl+F) with highlighting
2. Replace
3. Go to line
4. Word-wise cursor movement
5. Page up/down

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
├── Holds buffer state (lines, cursor, etc.)
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

### Unit Tests Needed
- [ ] Buffer state management (add/remove/switch)
- [ ] Text manipulation (insert, delete, selection)
- [ ] Undo/redo stack operations
- [ ] Cursor movement logic

### Integration Tests Needed
- [ ] Create buffer → appears in tab bar
- [ ] Switch tab → content changes
- [ ] Type text → persists on tab switch
- [ ] Open file → content loads correctly
- [ ] Save file → content written to disk

### Visual/E2E Tests (via ScenicMCP)
- [ ] Menu opens on click
- [ ] Menu closes on selection
- [ ] Tab selection highlights correctly
- [ ] Cursor visible and positioned correctly

---

## Notes

- GEdit is GTK-based, Quillex is Scenic-based - some features may need reimagining
- System clipboard integration requires platform-specific code
- File dialogs need custom implementation (Scenic has no native dialogs)
- Consider Wayland/X11 differences for Linux clipboard
