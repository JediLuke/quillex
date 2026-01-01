defmodule QuillEx.RootScene.Renderizer do
  require Logger

  # Height of the top bar (TabBar + IconMenu)
  @top_bar_height 35

  # Height of the search bar
  @search_bar_height 36

  # Helper for tab width menu labels with checkmark
  defp tab_width_label(width, current) when width == current, do: "#{width} Spaces  ✓"
  defp tab_width_label(width, _current), do: "#{width} Spaces"

  # it has to take in a scene here cause we need to cast to the scene's children
  # old_state is nil on init, or the previous state on updates
  #
  # Z-ORDER STRATEGY:
  # When any component needs recreation that could affect z-order, we delete
  # and recreate ALL components in the correct order (bottom to top):
  #   1. buffer_pane (bottom)
  #   2. search_bar (middle, when visible)
  #   3. tab_bar + icon_menu (top - dropdowns render above everything)
  def render(
    %Scenic.Graph{} = graph,
    %Scenic.Scene{} = scene,
    old_state,
    %QuillEx.RootScene.State{} = state
  ) do
    # Split frame: top bar and buffer pane below
    [top_bar_frame, buffer_frame] = Widgex.Frame.v_split(state.frame, px: @top_bar_height)

    # If search bar is visible, split buffer area further
    {search_bar_frame, actual_buffer_frame} =
      if state.show_search_bar do
        [search_frame, buf_frame] = Widgex.Frame.v_split(buffer_frame, px: @search_bar_height)
        {search_frame, buf_frame}
      else
        {nil, buffer_frame}
      end

    # Check if we need full z-order rebuild
    needs_reorder = needs_buffer_pane_recreation?(old_state, state)

    if needs_reorder do
      # Delete all and recreate in correct z-order
      graph
      |> Scenic.Graph.delete(:buffer_pane)
      |> Scenic.Graph.delete(:search_bar)
      |> Scenic.Graph.delete(:tab_bar)
      |> Scenic.Graph.delete(:icon_menu)
      |> do_create_buffer_pane(state, actual_buffer_frame)
      |> maybe_create_search_bar(state, search_bar_frame)
      |> render_top_bar(old_state, state, top_bar_frame)
    else
      # Incremental updates - z-order preserved
      graph
      |> maybe_update_search_bar(state, search_bar_frame)
      |> render_top_bar(old_state, state, top_bar_frame)
    end
  end

  # Create search bar if frame is provided (search bar visible)
  defp maybe_create_search_bar(graph, _state, nil), do: graph
  defp maybe_create_search_bar(graph, state, %Widgex.Frame{} = frame) do
    search_bar_data = %{
      id: :search_bar,
      frame: frame,
      query: state.search_query
    }

    graph
    |> ScenicWidgets.SearchBar.add_to_graph(
      search_bar_data,
      id: :search_bar,
      translate: frame.pin.point
    )
  end

  # Update search bar (add/remove) without full rebuild
  defp maybe_update_search_bar(graph, _state, nil) do
    # Search bar should be hidden
    case Scenic.Graph.get(graph, :search_bar) do
      [] -> graph
      _existing -> Scenic.Graph.delete(graph, :search_bar)
    end
  end

  defp maybe_update_search_bar(graph, state, %Widgex.Frame{} = frame) do
    case Scenic.Graph.get(graph, :search_bar) do
      [] ->
        # Need to add search bar - but this changes z-order!
        # For now, add it (will be below topbar since topbar exists)
        maybe_create_search_bar(graph, state, frame)

      _existing ->
        graph
    end
  end

  # Render top bar (tab bar + icon menu)
  defp render_top_bar(graph, old_state, state, frame) do
    icon_menu_width = 140
    tab_bar_width = frame.size.width - icon_menu_width

    tab_bar_frame = Widgex.Frame.new(
      pin: frame.pin.point,
      size: {tab_bar_width, frame.size.height}
    )

    icon_menu_frame = Widgex.Frame.new(
      pin: {elem(frame.pin.point, 0) + tab_bar_width, elem(frame.pin.point, 1)},
      size: {icon_menu_width, frame.size.height}
    )

    graph
    |> render_tab_bar(old_state, state, tab_bar_frame)
    |> render_icon_menu(state, icon_menu_frame)
  end

  defp render_tab_bar(graph, old_state, state, frame) do
    needs_recreation = needs_tab_bar_recreation?(old_state, state)

    case {Scenic.Graph.get(graph, :tab_bar), needs_recreation} do
      {[], _} ->
        do_create_tab_bar(graph, state, frame)

      {_existing, false} ->
        graph

      {_existing, true} ->
        graph
        |> Scenic.Graph.delete(:tab_bar)
        |> do_create_tab_bar(state, frame)
    end
  end

  defp render_icon_menu(graph, state, frame) do
    case Scenic.Graph.get(graph, :icon_menu) do
      [] ->
        menus = build_menus(state)
        icon_menu_data = %{
          frame: frame,
          menus: menus
        }

        graph
        |> ScenicWidgets.IconMenu.add_to_graph(
          icon_menu_data,
          id: :icon_menu,
          translate: frame.pin.point
        )

      _existing ->
        graph
    end
  end

  # Check if tab bar needs recreation
  defp needs_tab_bar_recreation?(nil, _new_state), do: true  # Initial render
  defp needs_tab_bar_recreation?(old_state, new_state) do
    # Compare buffer UUIDs (order matters for tabs)
    old_uuids = Enum.map(old_state.buffers, & &1.uuid)
    new_uuids = Enum.map(new_state.buffers, & &1.uuid)
    buffers_changed = old_uuids != new_uuids

    # Compare selected buffer
    old_selected = old_state.active_buf && old_state.active_buf.uuid
    new_selected = new_state.active_buf && new_state.active_buf.uuid
    selection_changed = old_selected != new_selected

    buffers_changed or selection_changed
  end

  # Helper to create tab bar
  defp do_create_tab_bar(graph, state, frame) do
    # Build tabs from open buffers
    tabs = Enum.map(state.buffers, fn buf ->
      %{
        id: buf.uuid,
        label: buf.name,
        closeable: true
      }
    end)

    # Select the active buffer's tab
    selected_id = if state.active_buf, do: state.active_buf.uuid, else: nil

    tab_bar_data = %{
      frame: frame,
      tabs: tabs,
      selected_id: selected_id
    }

    graph
    |> ScenicWidgets.TabBar.add_to_graph(
      tab_bar_data,
      id: :tab_bar,
      translate: frame.pin.point
    )
  end

  @doc """
  Build menus with current toggle states from state.
  """
  def build_menus(%QuillEx.RootScene.State{} = state) do
    [
      %{id: :file, icon: "F", items: [
        {"new", "New Buffer"},
        {"open", "Open File..."},
        {"save", "Save"},
        {"save_as", "Save As..."},
        {"close", "Close Buffer"}
      ]},
      %{id: :edit, icon: "E", items: [
        {"undo", "Undo (Ctrl+U)"},
        {"redo", "Redo (Ctrl+R)"},
        {"cut", "Cut"},
        {"copy", "Copy"},
        {"paste", "Paste"},
        {"find", "Find (Ctrl+F)"},
        {"find_next", "Find Next (Ctrl+G)"}
      ]},
      %{id: :view, icon: "V", items: [
        {"line_numbers", "Line Numbers", %{type: :toggle, checked: state.show_line_numbers}},
        {"word_wrap", "Word Wrap", %{type: :toggle, checked: state.word_wrap}},
        {"tab_width_2", tab_width_label(2, state.tab_width)},
        {"tab_width_3", tab_width_label(3, state.tab_width)},
        {"tab_width_4", tab_width_label(4, state.tab_width)},
        {"tab_width_8", tab_width_label(8, state.tab_width)}
      ]},
      %{id: :help, icon: "?", items: [
        {"about", "About Quillex"},
        {"shortcuts", "Keyboard Shortcuts"}
      ]}
    ]
  end

  # Check if buffer_pane needs to be recreated based on state changes
  defp needs_buffer_pane_recreation?(nil, _new_state), do: true  # Initial render
  defp needs_buffer_pane_recreation?(old_state, new_state) do
    # Recreate if active buffer changed
    old_uuid = old_state.active_buf && old_state.active_buf.uuid
    new_uuid = new_state.active_buf && new_state.active_buf.uuid
    buffer_changed = old_uuid != new_uuid

    # Recreate if editor settings changed (these affect TextField rendering)
    settings_changed =
      old_state.show_line_numbers != new_state.show_line_numbers or
      old_state.word_wrap != new_state.word_wrap or
      old_state.tab_width != new_state.tab_width

    # Recreate if search bar visibility changed (affects buffer frame size)
    layout_changed = old_state.show_search_bar != new_state.show_search_bar

    # Recreate if the buffer process PID changed (e.g., buffer was restarted by supervisor)
    # This ensures the TextField always has a valid buffer_controller reference
    buffer_pid_changed = if new_state.active_buf do
      old_pid = old_state.active_buf && get_buffer_pid(old_state.active_buf)
      new_pid = get_buffer_pid(new_state.active_buf)
      old_pid != new_pid
    else
      false
    end

    buffer_changed or settings_changed or layout_changed or buffer_pid_changed
  end

  # Helper to create the buffer_pane TextField
  defp do_create_buffer_pane(graph, state, frame) do
    # Fetch buffer to get content
    {:ok, buf} = Quillex.Buffer.Process.fetch_buf(state.active_buf)

    # Get the buffer process PID for buffer_backed mode
    buffer_pid = get_buffer_pid(state.active_buf)

    # Create font
    buffer_pane_state = Quillex.GUI.Components.BufferPane.State.new(%{})
    font = buffer_pane_state.font

    # Check if we have a cursor position to restore (from resize or saved in buffer)
    # Priority: 1) _restore_cursor from state (explicit restore), 2) buffer's saved cursor
    initial_cursor = Map.get(state, :_restore_cursor) || get_buffer_cursor(buf)

    # Check if we have a first visible line to restore (for scroll preservation during word wrap toggle)
    first_visible_line = Map.get(state, :_restore_first_visible_line)

    # TextField data for the active buffer (using state settings)
    wrap_mode = if state.word_wrap, do: :word, else: :none

    # Buffer should NOT be focused if search bar is visible (search bar takes focus)
    buffer_focused = not state.show_search_bar

    text_field_data = %{
      frame: frame,
      initial_text: Enum.join(buf.data, "\n"),
      mode: :multi_line,
      # BUFFER-BACKED MODE: TextField is now a view, Buffer.Process is source of truth
      input_mode: :buffer_backed,
      buffer_controller: buffer_pid,
      buffer_topic: {:buffers, buf.uuid},
      show_line_numbers: state.show_line_numbers,
      wrap_mode: wrap_mode,
      tab_width: state.tab_width,
      editable: true,
      focused: buffer_focused,
      font: %{
        name: font.name,
        size: font.size,
        metrics: font.metrics
      },
      colors: %{
        text: :white,
        background: buffer_pane_state.colors.slate,
        cursor: :white,
        line_numbers: {255, 255, 255, 85},
        border: :clear,
        focused_border: :clear
      },
      cursor_mode: :cursor,
      viewport_buffer_lines: 5,
      id: :buffer_pane
    }
    # Add initial_cursor if we're restoring from a resize or buffer switch
    |> maybe_add_cursor(initial_cursor)
    # Add first_visible_line if we're restoring scroll position (e.g., after word wrap toggle)
    |> maybe_add_first_visible_line(first_visible_line)

    graph
    |> ScenicWidgets.TextField.add_to_graph(
      text_field_data,
      id: :buffer_pane,
      translate: frame.pin.point
    )
  end

  # Helper to add initial_cursor to text_field_data if present
  defp maybe_add_cursor(data, nil), do: data
  defp maybe_add_cursor(data, cursor), do: Map.put(data, :initial_cursor, cursor)

  # Helper to add first_visible_line to text_field_data if present
  defp maybe_add_first_visible_line(data, nil), do: data
  defp maybe_add_first_visible_line(data, line), do: Map.put(data, :first_visible_line, line)

  # Extract cursor position from buffer's cursors field
  # Returns {line, col} tuple or nil if not available
  defp get_buffer_cursor(%{cursors: [%{line: line, col: col} | _]}) when line >= 1 and col >= 1 do
    {line, col}
  end
  defp get_buffer_cursor(_), do: nil

  # Get the buffer process PID from a BufRef
  defp get_buffer_pid(%Quillex.Structs.BufState.BufRef{uuid: uuid}) do
    buf_tag = {uuid, Quillex.Buffer.Process}
    case Registry.lookup(Quillex.BufferRegistry, buf_tag) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end
  defp get_buffer_pid(_), do: nil
end
