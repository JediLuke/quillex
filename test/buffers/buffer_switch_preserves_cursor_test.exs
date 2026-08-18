defmodule Quillex.Buffers.BufferSwitchPreservesCursorTest do
  @moduledoc """
  Locks in the cursor-preservation regression diagnosed in
  `docs/claude_notes/cursor_preservation_diagnosis_2026_05_02.md`.

  Bug summary: clicks delivered to the buffer-pane TextField (in
  `:store_backed` mode) via the non-positional
  `request_input([:cursor_button, ...])` channel get translated into
  `{:set_cursor, ...}` actions even when the click visually targeted a
  sibling overlay (an IconMenu dropdown rendered on top of the buffer
  pane). The result reproduced by `04_view_settings_spex.exs:370`: after
  the user clicks "File → New", the previously-active buffer's cursor is
  silently overwritten to end-of-line. Switching back and typing a marker
  then inserts it at end-of-line instead of the saved position.

  This test pins the reducer-layer contract that the fix introduces:

    * In `:store_backed` mode, a `:cursor_button` event whose local
      coordinates land inside the frame BUT well past the rendered text
      content of the clicked line is treated as overlay-class noise — the
      reducer does NOT emit `{:set_cursor, _}`.

  Diagnostic trace (verbatim, captured during the diagnosis pass):

      DIAG_TF_CLICK coords={1805.0, 18.0}  inside?=true   frame_pin={0, 35} frame_size={2000, 1165}
      DIAG_TF_CLICK_INSIDE → set_cursor={1, 17}
      DIAG_BUF_CAST buf_id=6a55a13a actions=[set_cursor: {1, 17}] → cursor=[col: 17]

  The line text is "Line one content" (16 chars × 20px ≈ 192px wide), but
  the click x is 1805 — far past any plausible end-of-line tolerance.
  Without the fix, `Reducer.input_to_buffer_action/2` returns
  `{:click_move_cursor, _, {:set_cursor, _}}`. With the fix, it returns
  `nil`.
  """

  use ExUnit.Case, async: true

  alias ScenicWidgets.TextField.{State, Reducer}
  alias Widgex.Frame
  alias Widgex.Scroll.ScrollState

  # IBMPlexMono is the default TextField font; load metrics from the TTF that
  # ships with scenic_widget_contrib so the click handler's downstream
  # `click_to_cursor → string_width` call can complete in :direct mode (where
  # the reducer is expected to fall through to the existing positioning path).
  @font_ttf Path.expand(
              "../../../scenic-widget-contrib/assets/fonts/IBMPlexMono-Regular.ttf",
              __DIR__
            )

  defp font_metrics do
    case TruetypeMetrics.load(@font_ttf) do
      {:ok, metrics} -> metrics
      _ -> nil
    end
  end

  # Build a minimal :store_backed TextField State suitable for driving the
  # `:cursor_button` clause in the reducer. Frame size matches the diagnostic
  # trace (a full-viewport buffer pane). Scroll is sized so neither scrollbar
  # is hit (otherwise the reducer's scrollbar-drag clause would consume the
  # click before the bug code path is reached).
  defp build_state(overrides \\ []) do
    frame = Frame.new(%{pin: {0, 35}, size: {2000, 1165}})
    scroll = ScrollState.new(frame, direction: :both, content_height: 100, content_width: 200)

    defaults = [
      frame: frame,
      lines: ["Line one content"],
      cursor: {1, 5},
      id: :test_text_field,
      input_mode: :store_backed,
      mode: :multi_line,
      focused: true,
      editable: true,
      selectable: true,
      show_line_numbers: true,
      line_number_width: 40,
      tab_width: 4,
      wrap_mode: :none,
      font: %{name: :ibm_plex_mono, size: 20, metrics: font_metrics()},
      colors: %{
        text: :white,
        background: :medium_slate_blue,
        cursor: :white,
        line_numbers: {255, 255, 255, 85},
        border: {80, 80, 100, 180},
        focused_border: {255, 215, 0}
      },
      scroll: scroll,
      cursor_visible: true,
      cursor_mode: :cursor,
      cursor_blink_rate: 500,
      max_visible_lines: 50,
      viewport_buffer_lines: 5,
      vertical_scroll_offset: 0,
      horizontal_scroll_offset: 0,
      selection: nil,
      max_lines: nil,
      show_scrollbars: false,
      scrollbar_width: 12,
      scrollbar_drag: nil,
      scrollbar_drag_start: nil,
      scrollbar_drag_offset: nil,
      text_drag: nil,
      text_drag_start: nil,
      last_click_time: nil,
      last_click_pos: nil,
      search_query: nil,
      search_matches: [],
      search_current_index: 0,
      undo_stack: [],
      redo_stack: [],
      undo_max_size: 100
    ]

    struct(State, Keyword.merge(defaults, overrides))
  end

  describe ":store_backed cursor_button — overlay-class click suppression" do
    # This block used to assert that a click landing far past the end of the
    # clicked line's text was DISCARDED, on the theory that it must have been
    # meant for something drawn above the pane. That guess cost more than it
    # bought: a click anywhere in the empty part of a document was thrown away,
    # and with it the FOCUS that click should have granted. Click below the
    # last line of a file — most of the surface of most new files — and the
    # editor went dead to the keyboard.
    #
    # Only the host knows whether something is drawn over the pane, and the
    # host already says so through `overlay_open`. That is the whole contract
    # now, and it is what these tests pin.
    test "an overlay-owned click is discarded" do
      state = build_state(overlay_open: true)

      action =
        Reducer.input_to_buffer_action(
          state,
          {:cursor_button, {:btn_left, 1, [], {1805.0, 18.0}}}
        )

      refute match?({:click_move_cursor, _, {:set_cursor, _}}, action),
             "a click while an overlay owns the pointer must not move the cursor — got #{inspect(action)}"

      refute match?({:double_click_select, _, _}, action),
             "a click while an overlay owns the pointer must not select — got #{inspect(action)}"
    end

    test "an overlay rect discards only the clicks inside it" do
      state = build_state(overlay_open: %{x: 1500, y: 0, width: 500, height: 200})

      inside =
        Reducer.input_to_buffer_action(
          state,
          {:cursor_button, {:btn_left, 1, [], {1805.0, 18.0}}}
        )

      refute match?({:click_move_cursor, _, {:set_cursor, _}}, inside),
             "a click inside the overlay's rect must not reach the document — got #{inspect(inside)}"

      outside =
        Reducer.input_to_buffer_action(
          state,
          {:cursor_button, {:btn_left, 1, [], {200.0, 18.0}}}
        )

      assert match?({:click_move_cursor, _, {:set_cursor, _}}, outside),
             "a click outside the overlay's rect belongs to the document — got #{inspect(outside)}"
    end

    test "with no overlay, a click in empty space places the cursor at end of line" do
      state = build_state()

      action =
        Reducer.input_to_buffer_action(
          state,
          {:cursor_button, {:btn_left, 1, [], {1805.0, 18.0}}}
        )

      assert match?({:click_move_cursor, _, {:set_cursor, {1, 17}}}, action),
             "clicking past the end of a line should put the cursor at EOL — got #{inspect(action)}"
    end

    test ":direct mode is unaffected" do
      state = build_state(input_mode: :direct)

      action =
        Reducer.input_to_buffer_action(
          state,
          {:cursor_button, {:btn_left, 1, [], {1805.0, 18.0}}}
        )

      assert match?({:click_move_cursor, _, {:set_cursor, _}}, action) or
               match?({:double_click_select, _, _}, action),
             ":direct mode click past EOL should still dispatch :set_cursor — got #{inspect(action)}"
    end
  end
end
