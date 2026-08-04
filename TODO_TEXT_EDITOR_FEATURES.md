# TextField Feature Roadmap

## Discussed / In Queue
- [ ] **Mouse controls** - click to position cursor, drag to select text

## Core Editing (Missing)
- [ ] **Select All** - Ctrl+A (works at buffer level, may need TextField integration)
- [ ] **Go to line** - Ctrl+G jump to line number (Ctrl+G currently mapped to Find Next)
- [ ] **Duplicate line** - Ctrl+Shift+D
- [ ] **Move line up/down** - Alt+Up/Down
- [ ] **Indent/Dedent** - Tab/Shift+Tab on selection
- [ ] **Auto-indent** - maintain indentation on newline

## Search & Replace
- [ ] **Case sensitive toggle**
- [ ] **Regex search** (advanced)

## Display & Rendering
- [ ] **Trailing whitespace** - optional visualization
- [ ] **Current line highlight** - subtle background on cursor line
- [ ] **Matching bracket highlight**
- [ ] **Minimap** (advanced)

## Selection & Cursors
- [ ] **Mouse click** - position cursor
- [ ] **Mouse drag** - select text
- [ ] **Double-click** - select word
- [ ] **Triple-click** - select line
- [ ] **Shift+click** - extend selection
- [ ] **Multiple cursors** (advanced)

## Status/Info
- [ ] **Status bar** - line:col, file name, encoding, line endings

## Settings
- [ ] **Tabs vs Spaces** - insert tabs or spaces
- [ ] **Line endings** - LF / CRLF
- [ ] **Encoding** - UTF-8 (display/handle)

## Performance
- [ ] **Large file handling** - virtual scrolling / lazy rendering
- [ ] **Syntax highlighting** (advanced - needs language parsers)

## Already Implemented
- [x] Multi-line editing
- [x] Cursor movement (arrows, home/end)
- [x] Horizontal & vertical scrolling
- [x] Scrollbar drag
- [x] Word wrap modes (none/word/char) — toggle in View menu
- [x] Line numbers with dynamic width — toggle in View menu
- [x] Copy/Cut/Paste (Ctrl+C/X/V)
- [x] Backspace/Delete
- [x] Basic text selection (keyboard, Shift+arrows)
- [x] Cursor blink
- [x] Find/Search (Ctrl+F) with search bar
- [x] Find Next (Ctrl+G) / Find Prev
- [x] Undo/Redo (Ctrl+U / Ctrl+R)
- [x] Save file (Ctrl+S)
- [x] Save As
- [x] Modified/dirty indicator (" *" on tab labels)
- [x] Tab rendering — configurable tab width (2/3/4/8 spaces)
- [x] Toggle sidebar (File Navigator)
- [x] File integrity verification (File menu → Verify File) — detect external file modifications
- [x] Delete line (Ctrl+D) — deletes current line
- [x] Replace / Replace All (Ctrl+H) — find and replace dialog
