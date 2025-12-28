# Spex/ScenicMCP Handover

## Goal
Use spex tests (in `test/spex/quillex/`) plus ScenicMCP tools to drive a true black-box, outside‑in dev loop for a basic text editor. Tests must validate what the UI actually renders, not just backend state.

## Key Insight
Current specs often read buffer state from `Quillex.Buffer.BufferManager`, but the UI is driven by `ScenicWidgets.TextField` in direct input mode and does not sync selection/cursor state back to the buffer process. This makes tests pass even when the UI is wrong (e.g., Shift+Arrow selection). Assertions should instead query the viewport/semantic viewport.

## Required Environment
- Spex runs require GLFW (cairo‑gtk target is broken for spex).
- Use:
  - `SCENIC_LOCAL_TARGET=glfw MIX_ENV=test mix spex test/spex/quillex/01_app_launch_spex.exs`
- This was validated; `01_app_launch_spex.exs` passes under GLFW.

## Run Status (last session)
- `SCENIC_LOCAL_TARGET=glfw MIX_ENV=test mix spex test/spex/quillex/01_app_launch_spex.exs` passed.
- Without GLFW, `scenic_driver_local` fails to link `take_screenshot` (only implemented in the glfw target).

## Files to Inspect First
- `test/spex/quillex/07_integration_v1_spex.exs` (selection assertions use backend state).
- `lib/gui/components/buffer_pane/buffer_pane.ex` (TextField direct input; text sync only).
- `lib/test_helpers/semantic_helpers.ex` (helpers for semantic viewport/scene data).

## Proposed Direction
1) Replace backend state assertions with semantic/viewport assertions.
   - Use ScenicMCP tools to read semantic viewport data and validate actual rendered text/selection.
2) For selection behavior, expose selection info in semantic data or emit selection events from TextField into BufferPane so specs can assert UI selection.
3) Expand coverage for user-visible behaviors (cursor position, selection highlight, clipboard ops) by reading semantic data rather than internal buffer state.

## Notes
- `AGENTS.md` updated with GLFW requirement for spex.
- ScenicMCP can also drive UI interactions (clicks, keystrokes) for faster loops.
