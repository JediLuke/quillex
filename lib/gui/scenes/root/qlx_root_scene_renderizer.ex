defmodule QuillEx.RootScene.Renderizer do
  require Logger

  import Scenic.Primitives, only: [group: 3, line: 3, rect: 3, rrect: 3, text: 3]

  alias Quillex.Utils.FileTree
  alias Quillex.Utils.SideNavThemes
  alias ScenicWidgets.FloatingPanel

  # Height of the top bar (TabBar + IconMenu)
  @top_bar_height 35

  # Height of the search bar
  @search_bar_height 36
  @search_popup_width 480
  @search_popup_margin 12

  # Height of the transient status notification bar
  @status_bar_height 24

  # Background colours for each severity level
  @status_color_info {60, 130, 70}
  @status_color_warning {170, 100, 30}
  @status_color_error {160, 40, 40}

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
    [top_bar_frame, buffer_frame] =
      Widgex.Frame.v_split(state.frame, px: scaled(@top_bar_height, state))

    # Find/Replace floats above the editor. Opening it must not resize or
    # recreate the buffer pane; that old layout transition was a major source
    # of perceived Ctrl+F latency on large documents.
    search_height =
      if state.show_replace,
        do: scaled(@search_bar_height * 2, state),
        else: scaled(@search_bar_height, state)

    search_bar_frame =
      if state.show_search_bar do
        margin = scaled(@search_popup_margin, state)

        FloatingPanel.frame(buffer_frame,
          placement: :top_right,
          margin: margin,
          size: {scaled(@search_popup_width, state), search_height}
        )
      else
        nil
      end

    remaining_frame = buffer_frame

    # The sidebar slot holds either the project-search pane or the file
    # navigator (search wins while open); both share file_nav_width.
    {file_nav_frame, content_frame} =
      if side_pane_open?(state) do
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
          Widgex.Frame.v_split(content_frame,
            px: content_height - scaled(@status_bar_height, state)
          )

        {stat_frame, buf_frame}
      else
        {nil, content_frame}
      end

    # Check if we need full z-order rebuild
    needs_reorder = needs_buffer_pane_recreation?(old_state, state)

    if needs_reorder do
      # Rebuild overlay children for z-order. Preserve the buffer pane when
      # only transient chrome (currently the status strip) changed.
      #
      # Recreating it opens a window where the outgoing TextField is still
      # alive and focused while the incoming one has not yet registered for
      # input: keystrokes there are lost, or applied to the document by the
      # dying instance (that is how search-bar keystrokes edited the file).
      #
      # A genuine geometry transition still recreates it until cursor-state
      # preservation across those transitions is fully unified with PaneStore.
      #
      # The pane follows the stable PaneStore source, including cursor and
      # active-buffer changes, so it survives transient chrome rebuilds.
      # Keeping that process alive is important for pointer input too:
      # deleting it during the short-lived "opened file" status transition
      # made the first wheel event disappear until a later click.
      graph =
        graph
        |> Scenic.Graph.delete(:status_bar)
        |> Scenic.Graph.delete(:file_nav)
        |> Scenic.Graph.delete(:project_search_pane)
        |> Scenic.Graph.delete(:file_nav_resize_handle_group)
        |> Scenic.Graph.delete(:search_bar)
        |> Scenic.Graph.delete(:tab_bar)
        |> Scenic.Graph.delete(:cursor_pos_label)
        |> Scenic.Graph.delete(:icon_menu)

      graph =
        if buffer_pane_geometry_changed?(old_state, state) do
          graph
          |> Scenic.Graph.delete(:buffer_pane)
          |> do_create_buffer_pane(state, actual_buffer_frame)
        else
          update_or_create_buffer_pane(graph, scene, state, actual_buffer_frame)
        end

      graph
      |> maybe_create_file_nav(state, file_nav_frame)
      |> maybe_create_status_bar(state, status_bar_frame)
      |> maybe_create_search_bar(state, search_bar_frame)
      |> maybe_create_file_nav_resize_handle(state, file_nav_frame)
      |> render_top_bar(scene, old_state, state, top_bar_frame)
    else
      # Incremental updates - z-order preserved
      apply_buffer_pane_settings(scene, old_state, state, actual_buffer_frame)
      apply_file_nav_frame(scene, old_state, state, file_nav_frame)

      graph
      |> maybe_move_buffer_pane(old_state, state, actual_buffer_frame)
      |> maybe_update_file_nav(state, file_nav_frame)
      |> maybe_update_status_bar(state, status_bar_frame)
      |> maybe_update_search_bar(scene, state, search_bar_frame)
      |> maybe_update_file_nav_resize_handle(state, file_nav_frame)
      |> render_top_bar(scene, old_state, state, top_bar_frame)
    end
  end

  # Update the stable pane in place (moving/resizing it) instead of recreating
  # it. This preserves input registration, cursor focus and pending events.
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
             show_matching_brace: state.show_matching_brace,
             highlight_current_line: state.highlight_current_line,
             highlight_current_column: state.highlight_current_column,
             wrap_mode: if(state.word_wrap, do: :word, else: :none),
             tab_width: state.tab_width,
             font: Quillex.GUI.Theme.editor_font(state.text_size),
             highlight_styles: highlight_styles(state),
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
        old_state.show_matching_brace != state.show_matching_brace or
        old_state.highlight_current_line != state.highlight_current_line or
        old_state.highlight_current_column != state.highlight_current_column or
        old_state.word_wrap != state.word_wrap or
        old_state.tab_width != state.tab_width or
        old_state.text_size != state.text_size or
        old_state.syntax_highlighting != state.syntax_highlighting or
        old_state.chrome_zoom != state.chrome_zoom or
        old_state.file_nav_width != state.file_nav_width or
        old_state.frame != state.frame or
        (old_state.file_nav_resizing and not state.file_nav_resizing)

    # During a divider drag, moving the existing pane primitive gives immediate
    # elastic feedback and the viewport clips its right edge. Reframing the
    # TextField on every pointer sample would invalidate word wrapping and
    # rebuild the entire wrapped projection dozens of times per second. Commit
    # the actual child frame once, on mouse-up.
    if changed? and not state.file_nav_resizing do
      Scenic.Scene.put_child(
        scene,
        :buffer_pane,
        {:update_settings,
         %{
           show_line_numbers: state.show_line_numbers,
           show_matching_brace: state.show_matching_brace,
           highlight_current_line: state.highlight_current_line,
           highlight_current_column: state.highlight_current_column,
           wrap_mode: if(state.word_wrap, do: :word, else: :none),
           tab_width: state.tab_width,
           font: Quillex.GUI.Theme.editor_font(state.text_size),
           highlight_styles: highlight_styles(state),
           frame: frame
         }}
      )
    end

    :ok
  end

  defp maybe_move_buffer_pane(graph, old_state, state, frame) do
    if old_state.file_nav_width != state.file_nav_width or old_state.frame != state.frame do
      Scenic.Graph.modify(graph, :buffer_pane, fn primitive ->
        Scenic.Primitive.put_transform(primitive, :translate, frame.pin.point)
      end)
    else
      graph
    end
  end

  defp apply_file_nav_frame(_scene, _old_state, _state, nil), do: :ok

  defp apply_file_nav_frame(scene, old_state, state, frame) do
    if old_state.file_nav_width != state.file_nav_width or old_state.frame != state.frame do
      Scenic.Scene.put_child(scene, side_pane_id(state), {:update_frame, frame})
    end

    :ok
  end

  defp highlight_styles(%{syntax_highlighting: true}), do: Quillex.GUI.Theme.highlight_styles()
  defp highlight_styles(_state), do: %{}

  @doc "Is anything showing in the sidebar slot?"
  def side_pane_open?(state), do: state.show_file_nav or state.show_project_search

  # Which child occupies the sidebar slot right now.
  defp side_pane_id(%{show_project_search: true}), do: :project_search_pane
  defp side_pane_id(_state), do: :file_nav

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
  defp maybe_update_search_bar(graph, _scene, _state, nil) do
    # Search bar should be hidden
    case Scenic.Graph.get(graph, :search_bar) do
      [] -> graph
      _existing -> Scenic.Graph.delete(graph, :search_bar)
    end
  end

  defp maybe_update_search_bar(graph, scene, state, %Widgex.Frame{} = frame) do
    case Scenic.Graph.get(graph, :search_bar) do
      [] ->
        # Need to add search bar - but this changes z-order!
        # For now, add it (will be below topbar since topbar exists)
        maybe_create_search_bar(graph, state, frame)

      _existing ->
        Scenic.Scene.put_child(scene, :search_bar, {:update_frame, frame})
        graph
    end
  end

  # Create the sidebar child if a frame is provided (something is visible)
  defp maybe_create_file_nav(graph, _state, nil), do: graph

  defp maybe_create_file_nav(graph, %{show_project_search: true} = state, %Widgex.Frame{} = frame) do
    tree = Quillex.GUI.ProjectSearchTree.build(project_search_snapshot(state))
    side_nav_theme = SideNavThemes.for_editor(scaled(24, state))

    graph
    |> ScenicWidgets.SideNav.add_to_graph(
      %{frame: frame, tree: tree, active_id: nil, theme: side_nav_theme},
      id: :project_search_pane,
      translate: frame.pin.point
    )
  end

  defp maybe_create_file_nav(graph, state, %Widgex.Frame{} = frame) do
    # Build file tree from current path
    file_tree = FileTree.build(state.file_nav_path || File.cwd!())

    # Sized against the editor's text, but deliberately smaller than it —
    # see SideNavThemes.for_editor/1.
    side_nav_theme = SideNavThemes.for_editor(scaled(24, state))

    side_nav_data = %{
      frame: frame,
      tree: file_tree,
      active_id: state.active_buf && state.active_buf.path,
      theme: side_nav_theme
    }

    graph
    |> ScenicWidgets.SideNav.add_to_graph(
      side_nav_data,
      id: :file_nav,
      translate: frame.pin.point
    )
  end

  # Update the sidebar (add/remove/swap) without full rebuild
  defp maybe_update_file_nav(graph, _state, nil) do
    graph
    |> Scenic.Graph.delete(:file_nav)
    |> Scenic.Graph.delete(:project_search_pane)
  end

  defp maybe_update_file_nav(graph, state, %Widgex.Frame{} = frame) do
    wanted = side_pane_id(state)
    other = if wanted == :file_nav, do: :project_search_pane, else: :file_nav
    graph = Scenic.Graph.delete(graph, other)

    case Scenic.Graph.get(graph, wanted) do
      [] -> maybe_create_file_nav(graph, state, frame)
      _existing -> graph
    end
  end

  # The scene mirrors the store snapshot; before the first one lands, draw
  # the pane empty rather than crash on nil.
  defp project_search_snapshot(%{project_search: nil}),
    do: %{root: nil, query: "", status: :idle, files: [], excluded: MapSet.new()}

  defp project_search_snapshot(%{project_search: snapshot}), do: snapshot

  defp maybe_create_file_nav_resize_handle(graph, _state, nil), do: graph

  defp maybe_create_file_nav_resize_handle(graph, state, %Widgex.Frame{} = frame) do
    hit_width = 32
    hit_height = 52
    bubble_size = if state.file_nav_resizing, do: 28, else: 24
    boundary_x = frame.pin.x + frame.size.width
    center_y = frame.pin.y + frame.size.height * 0.9

    {fill, stroke, arrow} =
      cond do
        state.file_nav_resizing ->
          {{205, 216, 236}, {235, 241, 250}, {42, 52, 72}}

        state.file_nav_resize_hovered ->
          {{72, 91, 126}, {150, 174, 220}, {225, 232, 245}}

        true ->
          {{55, 60, 72}, {105, 115, 135}, {180, 188, 205}}
      end

    group(
      graph,
      fn g ->
        g
        |> rect({hit_width, hit_height},
          id: :file_nav_resize_handle,
          fill: {:color, {0, 0, 0, 0}},
          input: [:cursor_pos, :cursor_button]
        )
        |> rrect({bubble_size, bubble_size, bubble_size / 2},
          id: :file_nav_resize_bubble,
          fill: fill,
          stroke: {1, stroke},
          translate: {(hit_width - bubble_size) / 2, (hit_height - bubble_size) / 2}
        )
        |> line({{9, 26}, {23, 26}}, id: :file_nav_resize_arrow_shaft, stroke: {2, arrow})
        |> line({{9, 26}, {13, 22}}, id: :file_nav_resize_arrow_left_up, stroke: {2, arrow})
        |> line({{9, 26}, {13, 30}}, id: :file_nav_resize_arrow_left_down, stroke: {2, arrow})
        |> line({{23, 26}, {19, 22}}, id: :file_nav_resize_arrow_right_up, stroke: {2, arrow})
        |> line({{23, 26}, {19, 30}}, id: :file_nav_resize_arrow_right_down, stroke: {2, arrow})
      end,
      id: :file_nav_resize_handle_group,
      translate: {boundary_x - hit_width / 2, center_y - hit_height / 2}
    )
  end

  defp maybe_update_file_nav_resize_handle(graph, state, frame) do
    graph
    |> Scenic.Graph.delete(:file_nav_resize_handle_group)
    |> maybe_create_file_nav_resize_handle(state, frame)
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
        |> text(msg,
          translate: {scaled(8, state), h - scaled(6, state)},
          fill: :white,
          font_size: scaled(14, state)
        )
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
    icon_menu_width = scaled(140, state)
    # "Ln 12, Col 34" label between the tabs and the icon menu (3.6): a
    # CursorPosLabel subscribed to the pane source — updates per keystroke
    # with no involvement from this scene (the store line in miniature).
    # Wide enough for five-digit lines and four-digit columns
    # ("Ln 12345, Col 1234") at 13pt mono, so the label keeps its even padding
    # instead of crowding the edges once a file gets long.
    cursor_label_width = scaled(170, state)
    tab_bar_width = frame.size.width - icon_menu_width - cursor_label_width

    tab_bar_frame =
      Widgex.Frame.new(
        pin: frame.pin.point,
        size: {tab_bar_width, frame.size.height}
      )

    cursor_label_frame =
      Widgex.Frame.new(
        pin: {elem(frame.pin.point, 0) + tab_bar_width, elem(frame.pin.point, 1)},
        size: {cursor_label_width, frame.size.height}
      )

    icon_menu_frame =
      Widgex.Frame.new(
        pin:
          {elem(frame.pin.point, 0) + tab_bar_width + cursor_label_width,
           elem(frame.pin.point, 1)},
        size: {icon_menu_width, frame.size.height}
      )

    graph
    |> render_tab_bar(scene, old_state, state, tab_bar_frame)
    |> render_cursor_pos_label(scene, old_state, state, cursor_label_frame)
    |> render_icon_menu(scene, old_state, state, icon_menu_frame)
  end

  defp render_cursor_pos_label(graph, scene, old_state, state, frame) do
    case Scenic.Graph.get(graph, :cursor_pos_label) do
      [] ->
        graph
        |> ScenicWidgets.CursorPosLabel.add_to_graph(
          %{
            frame: frame,
            source: Quillex.RadixCache.PaneStore.source(),
            font: %{name: :ibm_plex_mono, size: scaled(13, state)}
          },
          id: :cursor_pos_label,
          translate: frame.pin.point
        )

      _existing ->
        if old_state && old_state.frame != state.frame,
          do: Scenic.Scene.put_child(scene, :cursor_pos_label, {:update_frame, frame})

        move_component(graph, :cursor_pos_label, frame)
    end
  end

  defp render_tab_bar(graph, scene, old_state, state, frame) do
    needs_update = needs_tab_bar_recreation?(old_state, state)

    case {Scenic.Graph.get(graph, :tab_bar), needs_update} do
      {[], _} ->
        do_create_tab_bar(graph, state, frame)

      {_existing, false} ->
        if old_state.frame != state.frame,
          do: Scenic.Scene.put_child(scene, :tab_bar, {:update_frame, frame})

        move_component(graph, :tab_bar, frame)

      {_existing, true} ->
        # Message the surviving TabBar instead of delete+recreate: recreation
        # churn under rapid successive snapshots (e.g. dirty-flip then close)
        # can kill a TabBar mid-init.
        {tabs, selected_id} = derive_tabs(state)
        Scenic.Scene.put_child(scene, :tab_bar, {:set_tabs, tabs, selected_id})

        if old_state.frame != state.frame,
          do: Scenic.Scene.put_child(scene, :tab_bar, {:update_frame, frame})

        move_component(graph, :tab_bar, frame)
    end
  end

  defp render_icon_menu(graph, scene, old_state, state, frame) do
    case Scenic.Graph.get(graph, :icon_menu) do
      [] ->
        menus = build_menus(state)

        icon_menu_data = %{
          frame: frame,
          menus: menus,
          show_shortcuts: state.show_menu_shortcuts,
          # the library's theme defaults to the built-in :roboto_mono; quillex ships IBM Plex
          theme: %{
            font: :ibm_plex_mono,
            height: scaled(35, state),
            icon_button_size: scaled(35, state),
            icon_font_size: scaled(16, state),
            dropdown_item_height: scaled(28, state),
            dropdown_slider_height: scaled(52, state),
            dropdown_font_size: scaled(13, state)
          }
        }

        graph
        |> ScenicWidgets.IconMenu.add_to_graph(
          icon_menu_data,
          id: :icon_menu,
          translate: frame.pin.point
        )

      _existing ->
        if old_state && old_state.show_menu_shortcuts != state.show_menu_shortcuts,
          do:
            Scenic.Scene.put_child(
              scene,
              :icon_menu,
              {:show_shortcuts, state.show_menu_shortcuts}
            )

        if old_state && old_state.frame != state.frame,
          do: Scenic.Scene.put_child(scene, :icon_menu, {:update_frame, frame})

        move_component(graph, :icon_menu, frame)
    end
  end

  defp move_component(graph, id, frame) do
    Scenic.Graph.modify(graph, id, fn primitive ->
      Scenic.Primitive.put_transform(primitive, :translate, frame.pin.point)
    end)
  end

  # Check if tab bar needs recreation
  # Initial render
  defp needs_tab_bar_recreation?(nil, _new_state), do: true

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

    # External conflicts are durable buffer metadata. Unlike the transient
    # status message, the tab marker remains until reload/save resolves it.
    old_external = Enum.map(old_state.buffers, & &1.external_change)
    new_external = Enum.map(new_state.buffers, & &1.external_change)
    external_changed = old_external != new_external

    buffers_changed or selection_changed or dirty_changed or external_changed
  end

  # Helper to create tab bar
  # Build tabs from open buffers, appending " *" for dirty (unsaved) buffers
  defp derive_tabs(state) do
    tabs =
      Enum.map(state.buffers, fn buf ->
        label =
          buf.name <>
            if(buf.dirty?, do: " *", else: "") <>
            if(buf.external_change, do: " !", else: "")

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
      theme: %{
        font: :ibm_plex_mono,
        height: scaled(35, state),
        min_tab_width: scaled(100, state),
        max_tab_width: scaled(200, state),
        tab_padding: scaled(12, state),
        close_button_size: scaled(16, state),
        close_button_margin: scaled(8, state),
        font_size: scaled(13, state)
      }
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
    alias ScenicWidgets.Menu.Model.{Divider, Item, Select, Slider, Stepper, Toggle}

    command_item = fn id ->
      command = Quillex.Commands.fetch!(id)

      %Item{
        id: Atom.to_string(id),
        label: command.label,
        shortcut: command.shortcut,
        tooltip: command.description
      }
    end

    [
      %{
        id: :file,
        icon: :file,
        tooltip: "File commands",
        items: [
          command_item.(:new),
          command_item.(:open),
          command_item.(:save),
          command_item.(:save_as),
          %Item{
            id: "verify",
            label: "Verify File",
            tooltip: "Check whether the file on disk differs from this buffer."
          },
          %Item{
            id: "reload",
            label: "Reload from Disk",
            tooltip: "Discard buffer contents and reread the file from disk."
          },
          command_item.(:close)
        ]
      },
      %{
        id: :edit,
        icon: :edit,
        tooltip: "Editing commands",
        items: [
          command_item.(:undo),
          command_item.(:redo),
          command_item.(:cut),
          command_item.(:copy),
          command_item.(:paste),
          command_item.(:find),
          command_item.(:find_replace),
          command_item.(:find_next),
          command_item.(:find_in_project),
          command_item.(:replace_in_project)
        ]
      },
      %{
        id: :view,
        icon: :view,
        tooltip: "View and editor controls",
        items: [
          %Toggle{
            id: "file_nav",
            label: "File Navigator",
            checked?: state.show_file_nav,
            tooltip: "Show or hide the project file navigator."
          },
          %Toggle{
            id: "line_numbers",
            label: "Line Numbers",
            checked?: state.show_line_numbers,
            tooltip: "Show or hide source line numbers beside the editor."
          },
          %Toggle{
            id: "word_wrap",
            label: "Word Wrap",
            checked?: state.word_wrap,
            tooltip: "Wrap long lines at word boundaries instead of scrolling horizontally."
          },
          %Toggle{
            id: "matching_brace",
            label: "Show Matching Brace",
            checked?: state.show_matching_brace,
            tooltip: "Outline a brace beside the cursor and its matching partner."
          },
          %Toggle{
            id: "current_line_highlight",
            label: "Highlight Current Line",
            checked?: state.highlight_current_line,
            tooltip: "Draw a subtle horizontal guide beneath the current line."
          },
          %Toggle{
            id: "current_column_highlight",
            label: "Highlight Current Column",
            checked?: state.highlight_current_column,
            tooltip: "Draw a subtle vertical guide beneath the current column."
          },
          %Toggle{
            id: "syntax_highlighting",
            label: "Syntax Highlighting",
            checked?: state.syntax_highlighting,
            tooltip:
              "Mark keywords, names, strings and comments by weight, slant and underline (no colour needed)."
          },
          %Toggle{
            id: "action_feedback",
            label: "Action Feedback",
            checked?: state.show_action_feedback,
            tooltip: "Show low-level confirmations such as copied text, undo, and reload actions."
          },
          %Toggle{
            id: "menu_shortcuts",
            label: "Keyboard Shortcuts in Menus",
            checked?: state.show_menu_shortcuts,
            tooltip: "Show or hide the right-aligned shortcut column in menus."
          },
          %Divider{id: "view_display_divider"},
          %Slider{
            id: "text_size",
            label: "Text Size",
            value: state.text_size,
            min: 12,
            max: 32,
            tooltip: "Change the active editor font size from 12 to 32 points."
          },
          %Slider{
            id: "tab_width",
            label: "Tab Stops",
            value: state.tab_width,
            min: 2,
            max: 12,
            step: 1,
            tooltip: "Set the visual distance between tab stops from 2 to 12 spaces."
          },
          %Stepper{
            id: "chrome_zoom",
            label: "Zoom",
            value: state.chrome_zoom,
            min: 50,
            max: 200,
            step: 10,
            tooltip:
              "Scale application chrome independently from editor text. Ctrl/Cmd + or - changes it; Ctrl/Cmd 0 resets it."
          },
          %Divider{id: "view_folding_divider"},
          command_item.(:toggle_fold),
          command_item.(:unfold_all),
          %Select{
            id: "fold_level",
            label: "Set Fold Level",
            value: state.fold_level,
            options: [1, 2, 3, 4],
            tooltip: "Collapse all code blocks at the selected nesting level or deeper."
          }
        ]
      },
      %{
        id: :help,
        icon: :help,
        tooltip: "Help and keyboard shortcuts",
        items: [
          %Item{
            id: "about",
            label: "About Quillex",
            tooltip: "Show Quillex version and project information."
          },
          %Item{id: "shortcuts", label: "Keyboard Shortcuts"}
        ]
      }
    ]
  end

  defp scaled(value, state), do: max(1, round(value * state.chrome_zoom / 100))

  # Check if buffer_pane needs to be recreated based on state changes
  # Initial render
  defp needs_buffer_pane_recreation?(nil, _new_state), do: true

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
    # Recreate if search bar, replace mode, or file nav visibility changed (affects buffer frame size)
    # Recreate if status bar appears or disappears (carves @status_bar_height from content area)
    status_bar_changed = old_state.status_message == nil != (new_state.status_message == nil)

    buffer_pane_geometry_changed?(old_state, new_state) or status_bar_changed or
      old_state.chrome_zoom != new_state.chrome_zoom
  end

  defp buffer_pane_geometry_changed?(nil, _new_state), do: true

  defp buffer_pane_geometry_changed?(old_state, new_state) do
    # Search/replace is an overlay and does not participate in pane geometry.
    layout_changed = side_pane_open?(old_state) != side_pane_open?(new_state)

    # Viewport reshapes are intentionally NOT a recreation trigger. They arrive
    # in bursts while the user drags the window and every surviving child has
    # an in-place frame update path.
    layout_changed
  end

  # Helper to create the buffer_pane TextField
  defp do_create_buffer_pane(graph, state, frame) do
    # Fetch buffer to get content for the initial render (the TextField
    # hydrates from the pane's retained snapshot when one exists)
    {:ok, buf} = Quillex.Buffer.Process.fetch_buf(state.active_buf)

    # Create font
    font = Quillex.GUI.Theme.editor_font(state.text_size)
    colors = Quillex.GUI.Theme.editor_colors()

    # Check if we have a cursor position to restore (from resize or saved in buffer)
    # Priority: 1) _restore_cursor from state (explicit restore), 2) buffer's saved cursor
    initial_cursor = Map.get(state, :_restore_cursor) || get_buffer_cursor(buf)

    # Check if we have a first visible line to restore (for scroll preservation during word wrap toggle)
    first_visible_line = Map.get(state, :_restore_first_visible_line)

    # TextField data for the active buffer (using state settings)
    wrap_mode = if state.word_wrap, do: :word, else: :none

    # Buffer should NOT be focused if search bar is visible (search bar takes focus)
    buffer_focused = not state.show_search_bar

    text_field_data =
      %{
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
        # Token spans for whatever the pane shows, from the highlight store;
        # the style map says how each class is drawn (empty = plain text).
        highlight_source: Quillex.RadixCache.HighlightStore.source(),
        highlight_styles: highlight_styles(state),
        show_line_numbers: state.show_line_numbers,
        show_matching_brace: state.show_matching_brace,
        highlight_current_line: state.highlight_current_line,
        highlight_current_column: state.highlight_current_column,
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
          background: colors.slate,
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

  # Extract cursor position from buffer's cursor field
  # Returns {line, col} tuple or nil if not available
  defp get_buffer_cursor(%{cursor: %{line: line, col: col}}) when line >= 1 and col >= 1 do
    {line, col}
  end

  defp get_buffer_cursor(_), do: nil
end
