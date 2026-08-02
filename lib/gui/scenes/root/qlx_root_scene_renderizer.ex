defmodule QuillEx.RootScene.Renderizer do
  require Logger

  import Scenic.Primitives, only: [group: 3, rect: 3, text: 3]

  alias Quillex.Utils.FileTree
  alias Quillex.Utils.SideNavThemes

  # Height of the top bar (TabBar + IconMenu)
  @top_bar_height 35

  # Height of the search bar
  @search_bar_height 36

  # Height of the transient status notification bar
  @status_bar_height 24

  # Background colours for each severity level
  @status_color_info {60, 130, 70}
  @status_color_warning {170, 100, 30}
  @status_color_error {160, 40, 40}

  # Helper for tab width menu labels with checkmark
  defp tab_width_label(width, current) when width == current, do: "#{width} Spaces  ✓"
  defp tab_width_label(width, _current), do: "#{width} Spaces"

  # `_scene` is kept in the signature for API stability (callers pass the scene struct);
  # it is currently unused because rendering is pure graph-state transformation.
  # old_state is nil on init, or the previous state on updates.
  #
  # Z-ORDER STRATEGY:
  # When any component needs recreation that could affect z-order, we delete
  # and recreate ALL components in the correct order (bottom to top):
  #   1. buffer_pane (bottom)
  #   2. status_bar (above buffer, when a notification is active)
  #   3. search_bar (middle, when visible)
  #   4. tab_bar + icon_menu (top - dropdowns render above everything)

  # Guard: no frame means we cannot lay out components yet.  This happens during
  # process startup or in unit-test contexts where a bare state struct (frame: nil)
  # is passed.  Return the graph unchanged so callers don't crash.
  def render(%Scenic.Graph{} = graph, _scene, _old_state, %QuillEx.RootScene.State{frame: nil}) do
    graph
  end

  def render(
    %Scenic.Graph{} = graph,
    scene,
    old_state,
    %QuillEx.RootScene.State{} = state
  ) do
    # Split frame: top bar and buffer pane below
    [top_bar_frame, buffer_frame] = Widgex.Frame.v_split(state.frame, px: @top_bar_height)

    # If search bar is visible, split buffer area further
    # When replace mode is on, double the search bar height
    search_height = if state.show_replace, do: @search_bar_height * 2, else: @search_bar_height

    {search_bar_frame, remaining_frame} =
      if state.show_search_bar do
        [search_frame, buf_frame] = Widgex.Frame.v_split(buffer_frame, px: search_height)
        {search_frame, buf_frame}
      else
        {nil, buffer_frame}
      end

    # If file nav is visible, split horizontally for sidebar
    {file_nav_frame, content_frame} =
      if state.show_file_nav do
        [nav_frame, buf_frame] = Widgex.Frame.h_split(remaining_frame, px: state.file_nav_width)
        {nav_frame, buf_frame}
      else
        {nil, remaining_frame}
      end

    # If a status message is active, carve a thin bar from the bottom of the content area
    {status_bar_frame, actual_buffer_frame} =
      if state.status_message do
        content_height = content_frame.size.height
        [buf_frame, stat_frame] =
          Widgex.Frame.v_split(content_frame, px: content_height - @status_bar_height)
        {stat_frame, buf_frame}
      else
        {nil, content_frame}
      end

    # Check if we need full z-order rebuild
    needs_reorder = needs_buffer_pane_recreation?(old_state, state)

    if needs_reorder do
      # Rebuild the overlay children for z-order, but NEVER the buffer pane.
      #
      # Recreating it opens a window where the outgoing TextField is still
      # alive and focused while the incoming one has not yet registered for
      # input: keystrokes there are lost, or applied to the document by the
      # dying instance (that is how search-bar keystrokes edited the file).
      #
      # The pane keeps its original — earliest, therefore bottom — position
      # in the graph, and every overlay is recreated after it, so they still
      # render on top by construction.
      #
      # Three prerequisites were cleared to make this viable — no synchronous
      # reads into the pane, full recomputation of frame-derived values, and
      # virtualised rendering — and with them the in-place path runs clean in
      # isolation (29/29). Wiring it across the WHOLE suite, however, made two
      # cursor scenarios fail consistently (cursor preservation across a buffer
      # switch, and click-to-position): a surviving pane keeps its own cursor,
      # where a recreated one is rebuilt from the buffer's, and the two can
      # disagree. Reconciling that (make the pane's cursor strictly follow the
      # store on every publish) is the remaining step; until then recreation
      # stays, since it is measurably the more stable of the two.
      #
      # The input-corruption window is closed independently by blurring BEFORE
      # the re-render — see do_show_search_bar.
      graph
      |> Scenic.Graph.delete(:buffer_pane)
      |> Scenic.Graph.delete(:status_bar)
      |> Scenic.Graph.delete(:file_nav)
      |> Scenic.Graph.delete(:search_bar)
      |> Scenic.Graph.delete(:tab_bar)
      |> Scenic.Graph.delete(:cursor_pos_label)
      |> Scenic.Graph.delete(:icon_menu)
      |> maybe_create_file_nav(state, file_nav_frame)
      |> do_create_buffer_pane(state, actual_buffer_frame)
      |> maybe_create_status_bar(state, status_bar_frame)
      |> maybe_create_search_bar(state, search_bar_frame)
      |> render_top_bar(scene, old_state, state, top_bar_frame)
    else
      # Incremental updates - z-order preserved
      apply_buffer_pane_settings(scene, old_state, state, actual_buffer_frame)

      graph
      |> maybe_update_file_nav(state, file_nav_frame)
      |> maybe_update_status_bar(state, status_bar_frame)
      |> maybe_update_search_bar(state, search_bar_frame)
      |> render_top_bar(scene, old_state, state, top_bar_frame)
    end
  end

  # Kept for the day line rendering is virtualised: updates the existing pane
  # in place (moving/resizing it) instead of recreating it, which avoids the
  # input-loss window at the cost of a full in-component rebuild. See the
  # note in the reorder branch for why it is not wired up yet.
  @doc false
  def update_or_create_buffer_pane(graph, scene, state, frame) do
    case Scenic.Graph.get(graph, :buffer_pane) do
      [] ->
        do_create_buffer_pane(graph, state, frame)

      _existing ->
        Scenic.Scene.put_child(
          scene,
          :buffer_pane,
          {:update_settings,
           %{
             show_line_numbers: state.show_line_numbers,
             wrap_mode: if(state.word_wrap, do: :word, else: :none),
             tab_width: state.tab_width,
             frame: frame
           }}
        )

        # The component's own graph is rebuilt from the new frame's SIZE, but
        # its position in the parent comes from this translate.
        Scenic.Graph.modify(graph, :buffer_pane, fn primitive ->
          Scenic.Primitive.put_transform(primitive, :translate, frame.pin.point)
        end)
    end
  end

  # Push changed editor settings into the LIVE buffer pane instead of
  # rebuilding it. Keeping the component's process alive keeps its input
  # registration, focus and cursor — a recreation drops input that arrives
  # while the old instance is dying (a character can vanish if you type
  # while toggling a setting).
  defp apply_buffer_pane_settings(_scene, nil, _state, _frame), do: :ok

  defp apply_buffer_pane_settings(scene, old_state, state, frame) do
    changed? =
      old_state.show_line_numbers != state.show_line_numbers or
        old_state.word_wrap != state.word_wrap or
        old_state.tab_width != state.tab_width

    if changed? do
      Scenic.Scene.put_child(
        scene,
        :buffer_pane,
        {:update_settings,
         %{
           show_line_numbers: state.show_line_numbers,
           wrap_mode: if(state.word_wrap, do: :word, else: :none),
           tab_width: state.tab_width,
           frame: frame
         }}
      )
    end

    :ok
  end

  # Create search bar if frame is provided (search bar visible)
  defp maybe_create_search_bar(graph, _state, nil), do: graph
  defp maybe_create_search_bar(graph, state, %Widgex.Frame{} = frame) do
    search_bar_data = %{
      id: :search_bar,
      frame: frame,
      query: state.search_query,
      replace_mode: state.show_replace
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

  # Create file navigator sidebar if frame is provided (file nav visible)
  defp maybe_create_file_nav(graph, _state, nil), do: graph
  defp maybe_create_file_nav(graph, state, %Widgex.Frame{} = frame) do
    # Build file tree from current path
    file_tree = FileTree.build(state.file_nav_path || File.cwd!())

    # Use dark theme for file navigator (merlinex-inspired)
    side_nav_data = %{
      frame: frame,
      tree: file_tree,
      active_id: nil,
      theme: SideNavThemes.dark()
    }

    graph
    |> ScenicWidgets.SideNav.add_to_graph(
      side_nav_data,
      id: :file_nav,
      translate: frame.pin.point
    )
  end

  # Update file nav (add/remove) without full rebuild
  defp maybe_update_file_nav(graph, _state, nil) do
    # File nav should be hidden
    case Scenic.Graph.get(graph, :file_nav) do
      [] -> graph
      _existing -> Scenic.Graph.delete(graph, :file_nav)
    end
  end

  defp maybe_update_file_nav(graph, state, %Widgex.Frame{} = frame) do
    case Scenic.Graph.get(graph, :file_nav) do
      [] ->
        # Need to add file nav
        maybe_create_file_nav(graph, state, frame)

      _existing ->
        graph
    end
  end

  # Create status bar (transient notification strip at bottom of content area)
  defp maybe_create_status_bar(graph, _state, nil), do: graph
  defp maybe_create_status_bar(graph, state, %Widgex.Frame{} = frame) do
    bg_color = status_color(state.status_severity)
    {w, h} = {frame.size.width, frame.size.height}
    {tx, ty} = frame.pin.point
    msg = state.status_message || ""

    graph
    |> group(
      fn g ->
        g
        |> rect({w, h}, fill: bg_color)
        |> text(msg, translate: {8, h - 6}, fill: :white, font_size: 14)
      end,
      id: :status_bar,
      translate: {tx, ty}
    )
  end

  # Update status bar (add/remove/refresh) without full rebuild
  defp maybe_update_status_bar(graph, _state, nil) do
    case Scenic.Graph.get(graph, :status_bar) do
      [] -> graph
      _existing -> Scenic.Graph.delete(graph, :status_bar)
    end
  end

  defp maybe_update_status_bar(graph, state, %Widgex.Frame{} = frame) do
    graph
    |> Scenic.Graph.delete(:status_bar)
    |> maybe_create_status_bar(state, frame)
  end

  # Map severity atom to a background colour tuple
  defp status_color(:warning), do: @status_color_warning
  defp status_color(:error), do: @status_color_error
  defp status_color(_), do: @status_color_info

  # Render top bar (tab bar + icon menu)
  defp render_top_bar(graph, scene, old_state, state, frame) do
    icon_menu_width = 140
    # "Ln 12, Col 34" label between the tabs and the icon menu (3.6): a
    # CursorPosLabel subscribed to the pane source — updates per keystroke
    # with no involvement from this scene (the store line in miniature).
    cursor_label_width = 110
    tab_bar_width = frame.size.width - icon_menu_width - cursor_label_width

    tab_bar_frame = Widgex.Frame.new(
      pin: frame.pin.point,
      size: {tab_bar_width, frame.size.height}
    )

    cursor_label_frame = Widgex.Frame.new(
      pin: {elem(frame.pin.point, 0) + tab_bar_width, elem(frame.pin.point, 1)},
      size: {cursor_label_width, frame.size.height}
    )

    icon_menu_frame = Widgex.Frame.new(
      pin: {elem(frame.pin.point, 0) + tab_bar_width + cursor_label_width, elem(frame.pin.point, 1)},
      size: {icon_menu_width, frame.size.height}
    )

    graph
    |> render_tab_bar(scene, old_state, state, tab_bar_frame)
    |> render_cursor_pos_label(cursor_label_frame)
    |> render_icon_menu(state, icon_menu_frame)
  end

  defp render_cursor_pos_label(graph, frame) do
    case Scenic.Graph.get(graph, :cursor_pos_label) do
      [] ->
        graph
        |> ScenicWidgets.CursorPosLabel.add_to_graph(
          %{
            frame: frame,
            source: Quillex.RadixCache.PaneStore.source(),
            font: %{name: Quillex.GUI.Components.BufferPane.State.new(%{}).font.name, size: 13}
          },
          id: :cursor_pos_label,
          translate: frame.pin.point
        )

      _existing ->
        graph
    end
  end

  defp render_tab_bar(graph, scene, old_state, state, frame) do
    needs_update = needs_tab_bar_recreation?(old_state, state)

    case {Scenic.Graph.get(graph, :tab_bar), needs_update} do
      {[], _} ->
        do_create_tab_bar(graph, state, frame)

      {_existing, false} ->
        graph

      {_existing, true} ->
        # Message the surviving TabBar instead of delete+recreate: recreation
        # churn under rapid successive snapshots (e.g. dirty-flip then close)
        # can kill a TabBar mid-init.
        {tabs, selected_id} = derive_tabs(state)
        Scenic.Scene.put_child(scene, :tab_bar, {:set_tabs, tabs, selected_id})
        graph
    end
  end

  defp render_icon_menu(graph, state, frame) do
    case Scenic.Graph.get(graph, :icon_menu) do
      [] ->
        menus = build_menus(state)
        icon_menu_data = %{
          frame: frame,
          menus: menus,
          # the library's theme defaults to the built-in :roboto_mono; quillex ships IBM Plex
          theme: %{font: :ibm_plex_mono}
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

    # Compare dirty states (tab labels change when dirty flag changes)
    old_dirty = Enum.map(old_state.buffers, & &1.dirty?)
    new_dirty = Enum.map(new_state.buffers, & &1.dirty?)
    dirty_changed = old_dirty != new_dirty

    buffers_changed or selection_changed or dirty_changed
  end

  # Helper to create tab bar
  # Build tabs from open buffers, appending " *" for dirty (unsaved) buffers
  defp derive_tabs(state) do
    tabs = Enum.map(state.buffers, fn buf ->
      label = if buf.dirty?, do: buf.name <> " *", else: buf.name
      %{
        id: buf.uuid,
        label: label,
        closeable: true
      }
    end)

    # Select the active buffer's tab
    selected_id = if state.active_buf, do: state.active_buf.uuid, else: nil

    {tabs, selected_id}
  end

  defp do_create_tab_bar(graph, state, frame) do
    {tabs, selected_id} = derive_tabs(state)

    tab_bar_data = %{
      frame: frame,
      tabs: tabs,
      selected_id: selected_id,
      # the library's theme defaults to the built-in :roboto_mono; quillex ships IBM Plex
      theme: %{font: :ibm_plex_mono}
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
        {"save", "Save (Ctrl+S)"},
        {"save_as", "Save As..."},
        {"verify", "Verify File"},
        {"reload", "Reload from Disk"},
        {"close", "Close Buffer"}
      ]},
      %{id: :edit, icon: "E", items: [
        {"undo", "Undo (Ctrl+U)"},
        {"redo", "Redo (Ctrl+R)"},
        {"cut", "Cut (Ctrl+X)"},
        {"copy", "Copy (Ctrl+C)"},
        {"paste", "Paste (Ctrl+V)"},
        {"find", "Find (Ctrl+F)"},
        {"find_replace", "Find & Replace (Ctrl+H)"},
        {"find_next", "Find Next (Ctrl+G)"}
      ]},
      %{id: :view, icon: "V", items: [
        {"file_nav", "File Navigator", %{type: :toggle, checked: state.show_file_nav}},
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
    # NOTE: switching the active buffer does NOT recreate the buffer pane —
    # the TextField is a view over the stable pane source and PaneStore just
    # publishes a different document (same for buffer-process restarts: the
    # pane dispatch target is the PaneStore, never a raw buffer pid).

    # Editor settings are applied IN PLACE (see apply_buffer_pane_settings/3):
    # recreating the pane opens a window where the old TextField has died and
    # the new one has not yet requested input, and anything typed or clicked
    # in that window is lost. Settings alone therefore no longer force a
    # rebuild.
    settings_changed = false

    # Recreate if search bar, replace mode, or file nav visibility changed (affects buffer frame size)
    layout_changed = old_state.show_search_bar != new_state.show_search_bar or
      Map.get(old_state, :show_replace, false) != Map.get(new_state, :show_replace, false) or
      old_state.show_file_nav != new_state.show_file_nav

    # Recreate if status bar appears or disappears (carves @status_bar_height from content area)
    status_bar_changed = (old_state.status_message == nil) != (new_state.status_message == nil)

    # Recreate if the root frame changed (window resize / reshape). Every
    # child's frame is derived from it, so the incremental branch would leave
    # all of them rendered at their old sizes — the "internal app doesn't
    # resize" bug from the 2026-07-31 QA notes.
    frame_changed = old_state.frame != new_state.frame

    settings_changed or layout_changed or status_bar_changed or frame_changed
  end

  # Helper to create the buffer_pane TextField
  defp do_create_buffer_pane(graph, state, frame) do
    # Fetch buffer to get content for the initial render (the TextField
    # hydrates from the pane's retained snapshot when one exists)
    {:ok, buf} = Quillex.Buffer.Process.fetch_buf(state.active_buf)

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
      # STORE-BACKED: TextField is a pure view over the PANE — a stable
      # source/dispatch pair that never changes for the widget's life.
      # PaneStore follows the active buffer behind this contract, so buffer
      # switches are invisible here (see the store contract in
      # ScenicWidgets.TextField docs).
      input_mode: :store_backed,
      dispatch: Quillex.RadixCache.PaneStore,
      source: Quillex.RadixCache.PaneStore.source(),
      buffer_id: buf.uuid,
      show_line_numbers: state.show_line_numbers,
      wrap_mode: wrap_mode,
      tab_width: state.tab_width,
      # QA A5: a thin line either side of the text pane, none on top/bottom
      # (top would double the tab bar's edge; bottom hugs the window edge)
      border_sides: [:left, :right],
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
        border: {80, 80, 100, 180},
        focused_border: {255, 215, 0}
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
end
