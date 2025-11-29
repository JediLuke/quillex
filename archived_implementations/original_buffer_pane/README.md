# Original BufferPane Implementation

This directory contains the **original QuillEx BufferPane implementation** that was archived when migrating to the generic `ScenicWidgets.TextField` component from `scenic-widget-contrib`.

## Archive Date
November 28, 2025

## Why Archived
All the superior features from this implementation were ported to the generic TextField component, including:
- FontMetrics integration for accurate character positioning
- Optimized viewport rendering (only visible lines + buffer)
- Advanced cursor modes (:cursor, :block, :hidden)
- Semantic accessibility content
- Auto-scroll to cursor (ensure_cursor_visible)
- Efficient multi-line text insertion

## What's Preserved Here

### GUI Components
- `gui/components/buffer_pane/buffer_pane.ex` - Main Scenic component
- `gui/components/buffer_pane/buffer_pane_renderizer.ex` - Rendering engine (1,184 lines)
- `gui/components/cursor_caret/cursor_caret.ex` - Cursor component with blinking

### State & Input Handling
- `fluxus/buffer_pane/buffer_pane_state.ex` - BufferPane state management
- `fluxus/buffer_pane/buffer_pane_user_input_handler.ex` - Input routing

### Vim Keymappings (Still In Use!)
- `fluxus/buffer_pane/vim_key_mappings/gedit_notepad_map.ex` - Standard editor bindings
- `fluxus/buffer_pane/vim_key_mappings/vim_insert_mode_key_map.ex` - Vim insert mode
- `fluxus/buffer_pane/vim_key_mappings/vim_normal_mode_key_map.ex` - Vim normal mode
- `fluxus/buffer_pane/vim_key_mappings/vim_visual_mode_key_map.ex` - Vim visual mode

**Note:** The Vim keymapping files are still used by the new implementation! They were kept in the active codebase and connected to TextField via external input mode.

## Reference Use
This code is kept for reference purposes only. If you need to understand how something worked in the original implementation, you can refer to these files.

## New Implementation
The new implementation uses `ScenicWidgets.TextField` from `scenic-widget-contrib` with external input mode, connected to QuillEx's BufferProcess and Vim keymapping layers.
