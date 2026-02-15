# TextField Feature Roadmap

## Discussed / In Queue
- [ ] **Mouse controls** - click to position cursor, drag to select text
- [ ] **Tab rendering** - configurable tab width (2/4/8 spaces)
- [ ] **Find/Search** - Ctrl+F to find text, highlight matches, next/prev

## Core Editing (Missing)
- [ ] **Undo/Redo** - Ctrl+Z / Ctrl+Shift+Z
- [ ] **Select All** - Ctrl+A
- [ ] **Go to line** - Ctrl+G jump to line number
- [ ] **Delete line** - Ctrl+Shift+K or similar
- [ ] **Duplicate line** - Ctrl+D
- [ ] **Move line up/down** - Alt+Up/Down
- [ ] **Indent/Dedent** - Tab/Shift+Tab on selection
- [ ] **Auto-indent** - maintain indentation on newline

## File Operations
- [ ] **Save file** - Ctrl+S (write buffer back to disk)
- [ ] **Save As** - Ctrl+Shift+S
- [ ] **Reload from disk** - revert changes
- [ ] **Modified indicator** - show when buffer has unsaved changes

## Search & Replace
- [ ] **Find** - Ctrl+F with highlight matches
- [ ] **Find next/prev** - F3/Shift+F3 or Enter/Shift+Enter
- [ ] **Replace** - Ctrl+H
- [ ] **Replace all**
- [ ] **Case sensitive toggle**
- [ ] **Regex search** (advanced)

## Display & Rendering
- [ ] **Tab rendering** - show tabs as configurable width
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
- [ ] **Shift+arrows** - keyboard selection (may already work?)
- [ ] **Multiple cursors** (advanced)

## Status/Info
- [ ] **Status bar** - line:col, file name, encoding, line endings
- [ ] **Modified indicator** - asterisk or dot when unsaved

## Settings
- [ ] **Tab width** - 2/4/8 spaces
- [ ] **Tabs vs Spaces** - insert tabs or spaces
- [ ] **Line endings** - LF / CRLF
- [ ] **Encoding** - UTF-8 (display/handle)
- [ ] **Word wrap toggle** (already have!)
- [ ] **Line numbers toggle** (already have!)

## Performance
- [ ] **Large file handling** - virtual scrolling / lazy rendering
- [ ] **Syntax highlighting** (advanced - needs language parsers)

## Already Implemented
- [x] Multi-line editing
- [x] Cursor movement (arrows, home/end)
- [x] Horizontal & vertical scrolling
- [x] Scrollbar drag
- [x] Word wrap modes (none/word/char)
- [x] Line numbers with dynamic width
- [x] Copy/Cut/Paste (Ctrl+C/X/V)
- [x] Backspace/Delete
- [x] Basic text selection (keyboard)
- [x] Cursor blink
