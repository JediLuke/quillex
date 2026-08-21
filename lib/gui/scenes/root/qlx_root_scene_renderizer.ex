defmodule QuillEx.RootScene.Renderizer do
  require Logger

  import Scenic.Primitives, only: [group: 3, line: 3, rect: 3, rrect: 3, text: 3]

  alias Quillex.Utils.FileTree
  alias Quillex.Utils.SideNavThemes
  alias ScenicWidgets.FloatingPanel

  # Height of the top bar (TabBar + IconMenu)
  @top_bar_height 35

  # Height of the search bar
  # Taken from the component rather than guessed at. The bar owns its own
  # height, and a copy of it here drifts the moment the bar is restyled —
  # leaving the editor's frame carved for a bar of the wrong size.
  @search_bar_height ScenicWidgets.SearchBar.State.bar_height()
  @search_popup_width 480
  @search_popup_margin 12

  # Height of the transient status notification bar
  @status_bar_height 24

  # Background colours for each severity level
  # Colour lives in Quillex.GUI.Palette — one palette for the editor and every
  # piece of chrome. Nothing in this file names a colour.

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
      # The side pane is NOT in this list. It is a stable child like the buffer
      # pane: deleting it kills the SideNav process, and with it the expanded
      # folders, the selection and the scroll offset. Because every file
      # operation raises a status message, and a status message appearing or
      # disappearing lands here, recreating the pane meant the navigator
      # collapsed to its roots twice per drag-and-drop — once on the "Moved 2
      # entries" toast, once again when it cleared 8s later. The side pane's
      # frame is carved before the status strip (see the split above), so it is
      # not even geometrically affected by the transition that rebuilds it.
      # The tab bar is NOT in this list either, for the same reason the side
      # pane is not: every file operation raises a status message, a status
      # message appearing or disappearing lands here, and the collapse of the
      # sidebar raises one on top of its own layout change. Two rebuilds
      # arriving in the same breath killed a TabBar mid-init — the second
      # delete landing while the first replacement was still starting up.
      # render_tab_bar/5 already knows how to update a surviving instance in
      # place, and the tab bar cannot be overlapped by anything except the
      # icon-menu dropdown, which IS recreated here and so still lands above
      # it.
      graph =
        graph
        |> Scenic.Graph.delete(:status_bar)
        |> Scenic.Graph.delete(:file_nav_resize_handle_group)
        |> Scenic.Graph.delete(:search_bar)
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

      apply_file_nav_frame(scene, old_state, state, file_nav_frame)
      apply_theme(scene, old_state, state)

      graph
      |> maybe_update_file_nav(state, file_nav_frame)
      |> maybe_create_status_bar(state, status_bar_frame)
      |> maybe_create_search_bar(state, search_bar_frame)
      |> maybe_create_file_nav_resize_handle(state, file_nav_frame)
      |> render_top_bar(scene, old_state, state, top_bar_frame)
    else
      # Incremental updates - z-order preserved
      apply_buffer_pane_settings(scene, old_state, state, actual_buffer_frame)
      apply_file_nav_frame(scene, old_state, state, file_nav_frame)
      apply_theme(scene, old_state, state)

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
             colors: Quillex.GUI.Palette.text_field_colors(palette(state)),
             show_line_numbers: state.show_line_numbers,
             show_matching_brace: state.show_matching_brace,
             highlight_current_line: state.highlight_current_line,
             highlight_current_column: state.highlight_current_column,
             wrap_mode: if(state.word_wrap, do: :word, else: :none),
             auto_indent: state.auto_indent,
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
        old_state.auto_indent != state.auto_indent or
        old_state.tab_width != state.tab_width or
        old_state.text_size != state.text_size or
        old_state.syntax_highlighting != state.syntax_highlighting or
        old_state.theme != state.theme or
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
           colors: Quillex.GUI.Palette.text_field_colors(palette(state)),
           show_line_numbers: state.show_line_numbers,
           show_matching_brace: state.show_matching_brace,
           highlight_current_line: state.highlight_current_line,
           highlight_current_column: state.highlight_current_column,
           wrap_mode: if(state.word_wrap, do: :word, else: :none),
           auto_indent: state.auto_indent,
           tab_width: state.tab_width,
           font: Quillex.GUI.Theme.editor_font(state.text_size),
           highlight_styles: highlight_styles(state),
           frame: frame
         }}
      )
    end

    :ok
  end

  # A theme change repaints every surviving child in place. Rebuilding them
  # instead would work, but the side pane would lose its expanded folders and
  # its scroll offset — the same failure a status toast used to cause — and the
  # open dropdown would close under the pointer that just chose the theme.
  defp apply_theme(_scene, nil, _state), do: :ok

  # The chrome zoom is part of what a theme IS here — it decides every font
  # size and every control's size in the chrome. Comparing only `:theme` meant
  # zooming repainted nothing: the frames moved, because the layout reads the
  # zoom directly, and the type stayed exactly where it was. Tabs at 13pt in a
  # bar that had grown to 52.
  #
  # And so is the WINDOW, because `max_dropdown_height/1` is measured from it.
  # A window made smaller left the menus holding the height they were built
  # with, so the View dropdown believed it had room it no longer had: it drew
  # past the bottom of the viewport, and would not scroll, because by its own
  # arithmetic there was nothing to scroll.
  defp apply_theme(
         _scene,
         %{theme: theme, chrome_zoom: zoom, frame: frame},
         %{theme: theme, chrome_zoom: zoom, frame: frame}
       ),
       do: :ok

  defp apply_theme(scene, _old_state, state) do
    p = palette(state)

    Scenic.Scene.put_child(scene, :tab_bar, {:set_theme, tab_bar_theme(state)})
    Scenic.Scene.put_child(scene, :icon_menu, {:set_theme, icon_menu_theme(state)})

    Scenic.Scene.put_child(
      scene,
      :cursor_pos_label,
      {:set_theme, %{color: p.chrome_fg, background: p.chrome_bg}}
    )

    if state.show_project_search do
      Scenic.Scene.put_child(scene, :project_search_pane, {:set_theme, search_pane_theme(state)})
    end

    if state.show_file_nav do
      Scenic.Scene.put_child(scene, :file_nav, {:set_theme, file_nav_theme(state)})
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

  # First render: there is no pane to move yet, it is about to be created.
  defp apply_file_nav_frame(_scene, nil, _state, _frame), do: :ok

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
  @doc """
  Where the find bar floats, in the buffer pane's own coordinates.

  The pane is told an overlay is open so it stops acting on keys. Told `true`
  it also drops every CLICK, which is right for a dropdown and wrong for the
  find bar: clicking back into the document is how you resume editing, and a
  pane that ignores the click can never be handed the keyboard again. Given
  the rectangle instead, it drops only the clicks that land on the bar.
  """
  def search_bar_overlay_rect(state) do
    [_top_bar, buffer_frame] =
      Widgex.Frame.v_split(state.frame, px: scaled(@top_bar_height, state))

    height =
      if state.show_replace,
        do: scaled(@search_bar_height * 2, state),
        else: scaled(@search_bar_height, state)

    frame =
      FloatingPanel.frame(buffer_frame,
        placement: :top_right,
        margin: scaled(@search_popup_margin, state),
        size: {scaled(@search_popup_width, state), height}
      )

    pane_x = if side_pane_open?(state), do: state.file_nav_width, else: 0

    %{
      x: frame.pin.x - pane_x,
      y: frame.pin.y - scaled(@top_bar_height, state),
      width: frame.size.width,
      height: frame.size.height
    }
  end

  defp maybe_create_search_bar(graph, _state, nil), do: graph

  defp maybe_create_search_bar(graph, state, %Widgex.Frame{} = frame) do
    search_bar_data = %{
      id: :search_bar,
      frame: frame,
      query: state.search_query,
      replace_mode: state.show_replace,
      theme: Quillex.GUI.Palette.search_bar_theme(palette(state))
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
    graph
    |> ScenicWidgets.SearchPane.add_to_graph(
      %{
        frame: frame,
        # From the STORE, not this scene's cached snapshot. The cache is
        # written when the scene handles the store's publish — which it cannot
        # do while it is still inside the message that opened the pane and
        # pointed the search at a new project. Built from the cache, the pane
        # is born holding the previous project's root and never learns better,
        # because nothing publishes again until somebody searches.
        model:
          Quillex.RadixCache.ProjectSearchStore.get_state()
          |> Quillex.GUI.SearchPaneModel.build(),
        query: state.project_search_query,
        focus_field: state.project_search_focus_field,
        theme: search_pane_theme(state),
        focused: true
      },
      id: :project_search_pane,
      translate: frame.pin.point
    )
  end

  defp maybe_create_file_nav(graph, state, %Widgex.Frame{} = frame) do
    # Build file tree from current path
    nav_root = state.file_nav_path || File.cwd!()
    file_tree = FileTree.build(nav_root)

    # Sized against the editor's text, but deliberately smaller than it —
    # see SideNavThemes.for_editor/1.
    side_nav_theme = file_nav_theme(state)

    side_nav_data = %{
      frame: frame,
      tree: file_tree,
      active_id: state.active_buf && state.active_buf.path,
      theme: side_nav_theme,
      # Lets a drop on the empty space below the tree mean "move to the top
      # level"; without it there is no way to drag a file back out of a
      # subdirectory, because the root has no row of its own to aim at.
      root_id: nav_root
    }

    graph
    |> ScenicWidgets.SideNav.add_to_graph(
      side_nav_data,
      id: :file_nav,
      translate: frame.pin.point
    )
  end

  # The pane is chrome, so it is sized off the chrome zoom rather than the
  # editor's text size — a 24pt document must not turn the sidebar into a
  # billboard. Same reasoning as SideNavThemes.for_editor/1.
  # Every piece of chrome's theme is built by a NAMED function, and the same
  # function is used to create it and to repaint it. They used to be written
  # inline at the point of creation, which is why zooming the chrome moved the
  # frames and left the type behind: the repaint path had nothing to call but
  # the palette, and a palette carries colours.
  defp tab_bar_theme(state) do
    palette(state)
    |> Quillex.GUI.Palette.tab_bar_theme()
    |> Map.merge(%{
      font: :ibm_plex_mono,
      italic_font: :ibm_plex_mono_italic,
      height: scaled(35, state),
      min_tab_width: scaled(100, state),
      max_tab_width: scaled(200, state),
      tab_padding: scaled(12, state),
      close_button_size: scaled(16, state),
      close_button_margin: scaled(8, state),
      font_size: scaled(13, state)
    })
  end

  defp icon_menu_theme(state) do
    palette(state)
    |> Quillex.GUI.Palette.icon_menu_theme()
    |> Map.merge(%{
      font: :ibm_plex_mono,
      height: scaled(35, state),
      icon_button_size: scaled(35, state),
      icon_font_size: scaled(16, state),
      dropdown_item_height: scaled(28, state),
      dropdown_slider_height: scaled(52, state),
      dropdown_font_size: scaled(13, state),
      max_dropdown_height: max_dropdown_height(state),
      max_dropdown_width: max_dropdown_width(state)
    })
  end

  defp file_nav_theme(state),
    do: Quillex.Utils.SideNavThemes.for_editor(scaled(24, state), palette(state))

  defp search_pane_theme(state) do
    # Sized off the FILE NAVIGATOR, not off numbers of its own. The two share
    # the sidebar slot and show the same kind of thing — a list of file names
    # — and the pane's 13pt against the navigator's 17 made them look like
    # two applications. A result's file name is now exactly the size the
    # navigator would have drawn it, and everything else in the pane is
    # measured from that.
    label = Quillex.Utils.SideNavThemes.nav_font_size(scaled(24, state))

    palette(state)
    |> Quillex.GUI.Palette.search_pane_theme()
    |> Map.merge(%{
      font: :ibm_plex_mono,
      font_size: label,
      # Secondary type — the status line, the settings, the scope tree — a
      # step down from the results rather than a fixed 11.
      small_font_size: max(11, round(label * 0.8)),
      # The navigator's own row: the glyph plus breathing space.
      row_height: label + 10,
      field_height: label + 14,
      indent: 16
    })
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
  @doc false
  def project_search_snapshot(%{project_search: nil}), do: empty_search_snapshot()
  def project_search_snapshot(%{project_search: snapshot}), do: snapshot

  @doc false
  def empty_search_snapshot do
    %{
      root: nil,
      query: "",
      status: :idle,
      files: [],
      excluded: MapSet.new(),
      dismissed: MapSet.new(),
      dismissed_files: MapSet.new(),
      error: nil,
      case_sensitive: false,
      regex: false
    }
  end

  defp maybe_create_file_nav_resize_handle(graph, _state, nil), do: graph

  defp maybe_create_file_nav_resize_handle(graph, state, %Widgex.Frame{} = frame) do
    hit_width = 32
    hit_height = 52
    bubble_size = if state.file_nav_resizing, do: 28, else: 24
    boundary_x = frame.pin.x + frame.size.width
    center_y = frame.pin.y + frame.size.height * 0.9

    handle_state =
      cond do
        state.file_nav_resizing -> :dragging
        state.file_nav_resize_hovered -> :hovered
        true -> :idle
      end

    {fill, stroke, arrow} = Quillex.GUI.Palette.handle_colors(palette(state), handle_state)

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
    bg_color = Quillex.GUI.Palette.status_color(palette(state), state.status_severity)
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
          fill: palette(state).status_fg,
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
  defp palette(state), do: Quillex.GUI.Palette.get(state.theme)

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
            font: %{name: :ibm_plex_mono, size: scaled(13, state)},
            color: palette(state).chrome_fg,
            background: palette(state).chrome_bg
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
          theme: icon_menu_theme(state)
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

    # Promotion out of the preview slot is a visible change (the label loses
    # its italics) with no other trace in the buffer list.
    preview_changed = old_state.preview_buf_uuid != new_state.preview_buf_uuid

    buffers_changed or selection_changed or dirty_changed or external_changed or preview_changed
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
          closeable: true,
          # Italic marks the reusable preview tab — the one a search result
          # opens into, which the next result replaces. Slant rather than
          # colour, so it survives every theme and every kind of colour vision.
          style: if(buf.uuid == state.preview_buf_uuid, do: :italic, else: :normal)
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
      theme: tab_bar_theme(state)
    }

    graph
    |> ScenicWidgets.TabBar.add_to_graph(
      tab_bar_data,
      id: :tab_bar,
      translate: frame.pin.point
    )
  end

  # One radio row per theme. The list is short and fixed (five, deliberately),
  # so showing them all beats hiding them behind a submenu the user has to
  # discover — which is the whole point of item 8.
  defp theme_items(state) do
    Enum.map(Quillex.GUI.Palette.themes(), fn {id, label} ->
      %ScenicWidgets.Menu.Model.Radio{
        id: "theme_#{id}",
        label: label,
        group: "theme",
        value: id,
        selected?: state.theme == id,
        tooltip: "Use the #{label} colour scheme for the editor and the whole interface."
      }
    end)
  end

  # Two rows, same shape as the themes: a short fixed list is better shown
  # than hidden behind a submenu.
  defp modifier_items(state) do
    Enum.map(Quillex.Shortcuts.choices(), fn {id, label} ->
      %ScenicWidgets.Menu.Model.Radio{
        id: "primary_modifier_#{id}",
        label: label,
        group: "primary_modifier",
        value: id,
        selected?: state.primary_modifier == id,
        tooltip: "Use #{label} for shortcuts like Save and Copy, and print it in every menu."
      }
    end)
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
        # Rendered, not stored: the registry spells shortcuts with "Mod", and
        # what that key is called depends on the keyboard — Quillex.Shortcuts.
        shortcut: Quillex.Shortcuts.render(command.shortcut),
        tooltip: command.description
      }
    end

    [
      %{
        id: :file,
        icon: :file,
        tooltip: "File commands",
        items: [
          # Open a document, write a document, reconcile with disk, close.
          # Four jobs, four groups — the run of seven undivided rows read as
          # one list in which Save As and Verify File looked equally routine.
          command_item.(:new),
          command_item.(:open),
          %Divider{id: "file_write_divider"},
          command_item.(:save),
          command_item.(:save_as),
          %Divider{id: "file_disk_divider"},
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
          %Divider{id: "file_close_divider"},
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
          %Divider{id: "edit_clipboard_divider"},
          command_item.(:cut),
          command_item.(:copy),
          command_item.(:paste),
          %Divider{id: "edit_selection_divider"},
          command_item.(:select_all),
          command_item.(:delete_line),
          %Divider{id: "edit_find_divider"},
          command_item.(:find),
          command_item.(:find_replace),
          command_item.(:find_next),
          # Searching one buffer and searching the whole project are different
          # jobs on different surfaces; the divider says so.
          %Divider{id: "edit_project_divider"},
          command_item.(:find_in_project),
          command_item.(:replace_in_project),
          %Divider{id: "edit_navigate_divider"},
          command_item.(:goto_line)
        ]
      },
      %{
        id: :view,
        icon: :view,
        tooltip: "View and editor controls",
        items: [
          # What is on screen, then how the text itself is drawn, then folding,
          # then sizes, then the palette, then preferences about the interface.
          %Toggle{
            id: "file_nav",
            label: "File Navigator",
            checked?: state.show_file_nav,
            tooltip: "Show or hide the project file navigator."
          },
          %Divider{id: "view_text_divider"},
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
            id: "auto_indent",
            label: "Auto Indent",
            checked?: state.auto_indent,
            tooltip:
              "Carry the current line's indentation onto the next one when you press Enter."
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
          # Folding is three controls that belong together and read as one
          # idea. They used to sit alone below Zoom, after everything else,
          # which made "Set Fold Level" look like an afterthought rather than
          # the third member of a group.
          %Divider{id: "view_folding_divider"},
          command_item.(:toggle_fold),
          command_item.(:unfold_all),
          %Select{
            id: "fold_level",
            label: "Set Fold Level",
            value: state.fold_level,
            options: [1, 2, 3, 4],
            tooltip: "Collapse all code blocks at the selected nesting level or deeper."
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
              "Scale application chrome independently from editor text. " <>
                "#{Quillex.Commands.shortcut(:zoom_in)} and " <>
                "#{Quillex.Commands.shortcut(:zoom_out)} change it; " <>
                "#{Quillex.Commands.shortcut(:zoom_reset)} resets it."
          },
          # A bare list of five palette names needs a noun over it; the other
          # groups are legible from their rows and get a divider instead.
          %Divider{id: "view_theme_divider"},
          %Item{id: "theme_heading", label: "Theme", enabled?: false},
          theme_items(state),
          %Divider{id: "view_interface_divider"},
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
          # Which key means "command". A Mac user's hands know ⌘; a Linux
          # user's know Ctrl; and someone with a foot in both camps knows
          # whichever they decided on, which is why this is a setting and not
          # a detection. Changing it re-letters every shortcut in every menu.
          %Divider{id: "view_modifier_divider"},
          %Item{id: "modifier_heading", label: "Command Key", enabled?: false},
          modifier_items(state),
          # Changing a setting changes this session. Making it the one every
          # session starts with is a separate, deliberate act — so it is a
          # command sitting under the settings it saves, not a toggle.
          %Divider{id: "view_defaults_divider"},
          %Item{
            id: "save_default_settings",
            label: "Save Settings as Default",
            tooltip: "Start every future session with the settings you have now."
          },
          # The exclude list is a text file, and this is a text editor. That
          # is the whole of its "settings UI": open it, type, save.
          %Item{
            id: "edit_search_excludes",
            label: "Edit Search Excludes",
            tooltip: "What a project search skips, as a list you can change."
          }
        ]
        |> List.flatten()
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

  # How much room a dropdown has beneath the top bar. The View menu has grown
  # to five groups and scales with the chrome zoom, so at some combination of
  # zoom and window height it stops fitting — and a row below the window edge
  # cannot be clicked, which makes a feature that IS in the menu unreachable.
  # Handing the widget the number lets it clamp and scroll instead.
  defp max_dropdown_height(%{frame: nil}), do: nil

  defp max_dropdown_height(state) do
    max(state.frame.size.height - scaled(@top_bar_height, state) - 8, 100)
  end

  # The dropdown hangs off the right of the window and extends leftward, so
  # what bounds it is the window — not the icon strip it is anchored to, which
  # is 140px wide and was truncating every label longer than that.
  defp max_dropdown_width(%{frame: nil}), do: nil
  defp max_dropdown_width(state), do: max(state.frame.size.width - 16, 200)

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

    # Check if we have a cursor position to restore (from resize or saved in buffer)
    # Priority: 1) _restore_cursor from state (explicit restore), 2) buffer's saved cursor
    initial_cursor = Map.get(state, :_restore_cursor) || get_buffer_cursor(buf)

    # Check if we have a first visible line to restore (for scroll preservation during word wrap toggle)
    first_visible_line = Map.get(state, :_restore_first_visible_line)

    # TextField data for the active buffer (using state settings)
    wrap_mode = if state.word_wrap, do: :word, else: :none

    # Who holds the keyboard is recorded in the state, not inferred here. This
    # line used to read `not state.show_search_bar`, which meant that every
    # time the pane was recreated while the project search pane was open, the
    # buffer quietly took the keyboard back without the pane losing it — and
    # both consumed each keystroke.
    buffer_focused = state.keyboard_owner == :buffer and not state.show_search_bar

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
        auto_indent: state.auto_indent,
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
        colors: Quillex.GUI.Palette.text_field_colors(palette(state)),
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
