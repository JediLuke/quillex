defmodule QuillEx.RootScene do
  use Scenic.Scene
  alias QuillEx.RootScene
  require Logger

  # Layout constants — must stay in sync with qlx_root_scene_renderizer.ex
  @top_bar_height 35
  # Taken from the component rather than guessed at. The bar owns its own
  # height, and a copy of it here drifts the moment the bar is restyled —
  # leaving the editor's frame carved for a bar of the wrong size.
  @search_bar_height ScenicWidgets.SearchBar.State.bar_height()

  # Line height of the buffer pane text (must match BufferPane font_size).
  # Used to estimate the visible page size for Page Up / Page Down navigation.
  @line_height 24

  # Icon menu constants — must match ScenicWidgets.IconMenu default theme values
  # and the icon_menu_width used in qlx_root_scene_renderizer.ex
  @icon_menu_width 140
  @dropdown_width 180

  @file_nav_collapse_threshold 110
  @file_nav_min_width 160
  @file_nav_max_width 800

  # the way input works is that we route input to the active buffer
  # component, which then converts it to actions, which are then then
  # propagated back up - so basically input is handled at the "lowest level"
  # in the tree that we can route it to (i.e. before it needs to cause
  # some other higher-level state to re-compute), and these components
  # have the responsibility of converting the input to actions. The
  # Quillex.GUI.Components.Buffer component simply casts these up to it's
  # parent, which is this RootScene, which then processes the actions

  def init(%Scenic.Scene{} = scene, _args, _opts) do
    # if there aren't any buffers, initialize a new (empty) buffer on startup
    # checking with BufferManager on startup is cruicial for recovering from GUI crashes
    # cause we initialize with the correct state again
    buffers =
      case Quillex.Buffer.BufferManager.list_buffers() do
        [] ->
          # Quillex uses simple :edit mode (notepad-style)
          mode = Application.get_env(:quillex, :default_buffer_mode, :edit)
          Logger.info("Creating initial buffer with mode: #{inspect(mode)}")
          {:ok, buf_ref} = Quillex.Buffer.BufferManager.new_buffer(%{mode: mode})
          [buf_ref]

        buffers ->
          buffers
      end

    state =
      QuillEx.RootScene.State.new(%{
        frame: Widgex.Frame.new(scene.viewport),
        buffers: buffers
      })

    # need to pass in scene so we can cast to children, even though we would never do that during init
    # On init, old_state is nil (no previous state)
    graph = QuillEx.RootScene.Renderizer.render(Scenic.Graph.build(), scene, nil, state)

    scene =
      scene
      |> assign(state: state)
      |> assign(resize_scheduler: Quillex.GUI.ResizeScheduler.new())
      |> assign(graph: graph)
      |> push_graph(graph)

    Process.register(self(), __MODULE__)

    # Subscribe to the stores AFTER the first push: the retained snapshots
    # arrive as normal updates instead of racing init
    Scenic.PubSub.subscribe(Quillex.RadixCache.Sources.buffers())
    Scenic.PubSub.subscribe(Quillex.RadixCache.Sources.view())
    Scenic.PubSub.subscribe(Quillex.RadixCache.Sources.project_search())

    # Request input types for the root scene:
    # - :viewport  — resize/reshape events
    # - :cursor_pos — cursor tracking for scroll routing and close-on-outside-click
    # - :cursor_scroll — routing scroll events to the right child component
    # - :cursor_button — close-on-outside-click for menus and the search bar
    # - :key  — keyboard shortcuts (Ctrl+N, Ctrl+O, Ctrl+W, Ctrl+D)
    #           fired at root scene level so shortcuts work regardless of which
    #           child has focus.
    #
    # NOTE: Ctrl+H (Find & Replace) and Ctrl+F (Find) are intentionally NOT
    # handled here. They reach the root scene via the TextField → cast_parent
    # → handle_event path. Adding them to handle_input causes double-firing
    # (both handle_input AND handle_event fire for the same keystroke) which
    # crashes the root scene. The handle_event path alone is sufficient.
    #
    # TextField (child component) also independently requests :cursor_button for
    # cursor positioning and :key for text editing. Both can coexist: they are
    # separate GenServer processes and each receives its own copy of the event.
    # The root scene handlers guard on specific Ctrl+key combos, so regular
    # keystrokes fall through to the catch-all with no side effects.
    request_input(scene, [:viewport, :cursor_pos, :cursor_scroll, :cursor_button, :key])

    {:ok, scene}
  end

  # NOTE: "Verify File" (run_verification) has no keyboard shortcut.
  # The original Ctrl+V+F design used string-format patterns that Scenic 0.12
  # never delivers (Scenic uses atom keys like :key_f, not strings like "f").
  # Additionally, "v" is not a GLFW modifier key, so the chord cannot be
  # expressed as a simultaneous modifier combination. Access via File menu only.

  # Go to Line prompt owns the keyboard entirely while it is open. These clauses
  # come FIRST so a digit does not also trip a document shortcut underneath.
  def handle_input({:key, {key, 1, _mods}}, _context, %{assigns: %{state: %{show_goto_line: true}}} = scene) do
    state = scene.assigns.state

    case key do
      :key_enter ->
        commit_goto_line(scene)

      :key_kp_enter ->
        commit_goto_line(scene)

      # Scenic reports Escape as :key_esc; :key_escape is accepted too so the
      # prompt does not depend on which spelling a driver happens to send.
      k when k in [:key_esc, :key_escape] ->
        {:noreply, hide_goto_line(scene)}

      :key_backspace ->
        {:noreply, update_goto_line(scene, String.slice(state.goto_line_input, 0..-2//1))}

      _ ->
        case goto_line_digit(key) do
          nil -> {:noreply, scene}
          d -> {:noreply, update_goto_line(scene, state.goto_line_input <> d)}
        end
    end
  end

  # Swallow key-release and codepoint events too, so nothing leaks to the
  # document while the prompt is up.
  def handle_input({:key, {_key, 0, _mods}}, _context, %{assigns: %{state: %{show_goto_line: true}}} = scene),
    do: {:noreply, scene}

  def handle_input({:codepoint, _}, _context, %{assigns: %{state: %{show_goto_line: true}}} = scene),
    do: {:noreply, scene}

  # Handle Ctrl+N keyboard shortcut for New Buffer
  # Creates a new empty buffer, equivalent to File → New Buffer.
  def handle_input({:key, {:key_n, 1, [:ctrl]}}, _context, scene) do
    handle_cast({:action, :new_buffer}, scene)
  end

  # Handle Ctrl+O keyboard shortcut for Open File
  # Opens the file picker modal in open mode, equivalent to File → Open.
  def handle_input({:key, {:key_o, 1, [:ctrl]}}, _context, scene) do
    show_file_picker(scene)
  end

  # Handle Ctrl+W keyboard shortcut for Close Buffer
  # If the active buffer has unsaved changes, shows a Save/Discard/Cancel dialog.
  # If the buffer is clean (or there is no active buffer), closes immediately.
  def handle_input({:key, {:key_w, 1, [:ctrl]}}, _context, scene) do
    try_close_active_buffer(scene)
  end

  # Ctrl+Shift+F / Ctrl+Shift+H — find / replace across the project. Plain
  # Ctrl+F/H are NOT handled here (see the note above): they come up from
  # the focused TextField or the search bar as events. The shifted chords
  # never do, so this is their only entry point.
  #
  # Both open the same pane. The pane carries a replacement field at all times,
  # so there is nothing for the shifted-H variant to reveal — it exists because
  # people's fingers know it, and it lands on the replacement field.
  def handle_input({:key, {key, 1, mods}}, _context, scene)
      when key in [:key_f, :key_h] and is_list(mods) do
    if :shift in mods and Enum.any?(mods, &(&1 in [:ctrl, :meta, :super])) do
      open_project_search(scene, focus: if(key == :key_h, do: :replace, else: :query))
    else
      {:noreply, scene}
    end
  end

  def handle_input({:key, {key, 1, mods}}, _context, scene)
      when key in [:key_equal, :key_kp_add, :"key_="] do
    if Enum.any?(mods, &(&1 in [:ctrl, :meta, :super])), do: adjust_chrome_zoom(10)
    {:noreply, scene}
  end

  def handle_input({:key, {key, 1, mods}}, _context, scene)
      when key in [:key_minus, :key_kp_subtract, :"key_-"] do
    if Enum.any?(mods, &(&1 in [:ctrl, :meta, :super])), do: adjust_chrome_zoom(-10)
    {:noreply, scene}
  end

  def handle_input({:key, {:key_0, 1, mods}}, _context, scene) do
    if Enum.any?(mods, &(&1 in [:ctrl, :meta, :super])),
      do: Quillex.RadixCache.ViewStore.set_chrome_zoom(100)

    {:noreply, scene}
  end

  # Handle Ctrl+D keyboard shortcut for Delete Line.
  # Deletes the entire line under the cursor and moves the cursor to column 1
  # on the same line number (or the new last line if the bottom line was deleted).
  # When only one line remains the buffer is cleared to a single empty line.
  # Supports undo via Ctrl+Z.
  def handle_input({:key, {:key_d, 1, [:ctrl]}}, _context, scene) do
    dispatch_to_active_buffer(scene, :delete_line)
  end

  # Folding commands are view-only TextField actions. They are handled at the
  # root so the command registry and Help dialog describe real shortcuts even
  # when focus has just moved between editor children.
  def handle_input({:key, {:key_left_bracket, 1, mods}}, _context, scene)
      when mods in [[:ctrl, :alt], [:alt, :ctrl]] do
    if keyboard_overlay_open?(scene.assigns.state) do
      {:noreply, scene}
    else
      {line, _col} = get_buffer_cursor(scene) || {1, 1}
      Scenic.Scene.put_child(scene, :buffer_pane, {:action, {:toggle_fold, line}})
      {:noreply, scene}
    end
  end

  def handle_input({:key, {:key_right_bracket, 1, mods}}, _context, scene)
      when mods in [[:ctrl, :alt], [:alt, :ctrl]] do
    unless keyboard_overlay_open?(scene.assigns.state) do
      Scenic.Scene.put_child(scene, :buffer_pane, {:action, :unfold_all})
    end

    {:noreply, scene}
  end

  # Handle Ctrl+Home — move cursor to the very start of the document (line 1, col 1).
  # Mirrors GEdit behaviour: jumps to the beginning of the file regardless of current
  # position, clearing any active selection.
  def handle_input({:key, {:key_home, 1, [:ctrl]}}, _context, scene) do
    dispatch_to_active_buffer(scene, {:move_cursor, :doc_start})
  end

  # Handle Ctrl+End — move cursor to the end of the last line in the document.
  # Mirrors GEdit behaviour: jumps to the end of the file regardless of current
  # position, clearing any active selection.
  def handle_input({:key, {:key_end, 1, [:ctrl]}}, _context, scene) do
    dispatch_to_active_buffer(scene, {:move_cursor, :doc_end})
  end

  # Ctrl+Shift+Home / Ctrl+Shift+End — the same jumps, selecting on the way.
  # Every other movement key extends the selection when Shift is held, and
  # these are movement keys.
  def handle_input({:key, {:key_home, 1, mods}}, _context, scene)
      when is_list(mods) do
    if :ctrl in mods and :shift in mods do
      dispatch_to_active_buffer(scene, {:select_to, {1, 1}})
    else
      {:noreply, scene}
    end
  end

  def handle_input({:key, {:key_end, 1, mods}}, _context, scene)
      when is_list(mods) do
    if :ctrl in mods and :shift in mods do
      dispatch_to_active_buffer(scene, {:select_to, document_end(scene)})
    else
      {:noreply, scene}
    end
  end

  # Handle Page Up — move cursor up by roughly one screen-height of lines.
  # Page size is estimated from the viewport frame height minus the top bar,
  # divided by the buffer line height. Matches GEdit behaviour: cursor jumps
  # upward by a page, clamping at line 1. Clears any active selection.
  def handle_input({:key, {:key_pageup, 1, _mods}}, _context, scene) do
    page_size = compute_page_size(scene)
    dispatch_to_active_buffer(scene, {:move_cursor, {:page_up, page_size}})
  end

  # Handle Page Down — move cursor down by roughly one screen-height of lines.
  # Same page size logic as Page Up; clamps at the last line of the document.
  def handle_input({:key, {:key_pagedown, 1, _mods}}, _context, scene) do
    page_size = compute_page_size(scene)
    dispatch_to_active_buffer(scene, {:move_cursor, {:page_down, page_size}})
  end

  # NOTE: Ctrl+Left/Right (word navigation) are handled in the TextField's
  # input_to_buffer_action/2 directly, NOT here. Adding them here caused
  # double-firing: both root scene AND TextField processed each keypress,
  # resulting in two actions sent to the buffer (e.g. :next_word then
  # :move_cursor :right 1), landing the cursor at the wrong position.
  # The TextField sends {:move_cursor, :prev_word} / {:move_cursor, :next_word}
  # to the buffer controller in store_backed mode, which is the single
  # correct code path.

  def handle_input({:viewport, {input, _coords}}, _context, scene)
      when input in [:enter, :exit] do
    # don't do anything when the mouse enters/leaves the viewport
    {:noreply, scene}
  end

  def handle_input(
        {:viewport, {:reshape, {_new_vp_width, _new_vp_height} = new_vp_size}},
        _context,
        scene
      ) do
    current = scene.assigns.state.frame.size.box

    if current == new_vp_size do
      {:noreply, scene}
    else
      {scheduler, action} =
        Quillex.GUI.ResizeScheduler.enqueue(scene.assigns.resize_scheduler, new_vp_size)

      if action == :schedule, do: Process.send_after(self(), :apply_pending_viewport_resize, 16)
      {:noreply, assign(scene, resize_scheduler: scheduler)}
    end
  end

  def handle_info(:apply_pending_viewport_resize, scene) do
    {size, scheduler} = Quillex.GUI.ResizeScheduler.take(scene.assigns.resize_scheduler)
    scene = assign(scene, resize_scheduler: scheduler)

    case size do
      nil ->
        {:noreply, scene}

      size ->
        Quillex.PerfMonitor.measure(:viewport_resize, fn -> resize_viewport(scene, size) end)
    end
  end

  defp resize_viewport(scene, new_vp_size) do
    old_state = scene.assigns.state
    current_size = old_state.frame.size.box

    if current_size == new_vp_size do
      {:noreply, scene}
    else
      Logger.debug("#{__MODULE__} reshape: #{inspect(current_size)} -> #{inspect(new_vp_size)}")
      new_state = %{old_state | frame: Widgex.Frame.new(pin: {0, 0}, size: new_vp_size)}

      graph =
        QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

      {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}
    end
  end

  # File navigator resize drag. The root scene owns this short-lived gesture;
  # ViewStore remains authoritative for the committed width and visibility.
  def handle_input({:cursor_pos, {x, _y} = coords}, _context, scene)
      when scene.assigns.state.file_nav_resizing do
    state = scene.assigns.state

    max_width =
      min(@file_nav_max_width, max(@file_nav_min_width, trunc(state.frame.size.width - 240)))

    hide? = x < @file_nav_collapse_threshold

    width = x |> round() |> max(@file_nav_min_width) |> min(max_width)

    new_state = %{
      state
      | cursor_pos: coords,
        file_nav_width: width,
        file_nav_resize_hide?: hide?
    }

    # Keep the gesture scene-owned so ViewStore receives one durable commit on
    # release, while incrementally reframing the existing children for live
    # feedback. Renderizer's width path preserves both component PIDs; it only
    # updates their frames/transforms and the divider graph.
    new_graph =
      QuillEx.RootScene.Renderizer.render(
        scene.assigns.graph,
        scene,
        state,
        new_state
      )

    new_scene =
      scene
      |> assign(state: new_state, graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  # RootScene requests cursor input itself, so use explicit bounds rather than
  # relying on Scenic to choose the pill as the positional-input context. That
  # remains reliable even when the adjacent child component overlaps its edge.
  def handle_input({:cursor_pos, coords}, _context, scene) do
    maybe_clear_icon_menu_hover(scene, scene.assigns.state.cursor_pos, coords)
    update_file_nav_resize_hover(scene, coords, file_nav_resize_handle_hit?(scene, coords))
  end

  def handle_input(
        {:cursor_button, {:btn_left, 0, _mods, _coords}},
        _context,
        %{assigns: %{state: %{file_nav_resizing: true}}} = scene
      ) do
    :ok = release_input(scene, [:cursor_pos, :cursor_button])
    state = scene.assigns.state

    scene =
      if state.file_nav_resize_hide? do
        # Closed AND announced in one commit. Done as two casts, this
        # published two snapshots a few milliseconds apart, and each one is a
        # layout change: the sidebar going away, then the status strip
        # appearing. Two full chrome rebuilds in the same breath, with the
        # second delete landing while the first replacement was still
        # initialising — which is how an IconMenu ended up killed mid-init.
        Quillex.RadixCache.ViewStore.close_file_nav("File navigator hidden")
        scene
      else
        Quillex.RadixCache.ViewStore.set_file_nav_width(state.file_nav_width)
        scene
      end

    new_state = %{
      state
      | file_nav_resizing: false,
        file_nav_resize_hovered: false,
        file_nav_resize_hide?: false
    }

    graph = QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, state, new_state)

    new_scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    {:noreply, new_scene}
  end

  # Scroll is not routed from here. Both scrollable children — the buffer pane
  # (TextField) and the file navigator (SideNav) — request :cursor_scroll
  # themselves and bounds-check the pointer against their own frame, which is
  # the one mechanism that works for positional input a component does not
  # declare on a primitive. This scene used to forward wheel events to
  # :file_nav via put_child, which is why the sidebar never scrolled.

  # Close-on-outside-click: intercept left-button presses to dismiss open menus
  # and overlays when the user clicks outside them.
  #
  # Two behaviours implemented here:
  #
  #   1. **Icon menu dropdown** — When a dropdown is open and the user clicks in
  #      the editor area (y > top bar, x safely outside the dropdown x-range),
  #      we send {:close_menu} to the IconMenu child.  We only fire this when the
  #      click is to the LEFT of the full dropdown extent (icon_menu_width +
  #      dropdown_width from the right edge) to avoid a race condition between
  #      this handler and the IconMenu's own click handler.
  #
  #   2. **Search bar** — When the search bar is visible and the user clicks in
  #      the buffer area below it (y > top_bar + search_bar height), we close the
  #      search bar and return focus to the buffer pane.
  #
  # The FilePicker already handles close-on-outside-click internally (it renders
  # a full-screen overlay and cancels when the overlay is clicked).
  def handle_input({:cursor_button, {:btn_left, 1, _mods, {click_x, click_y}}}, _context, scene) do
    if file_nav_resize_handle_hit?(scene, {click_x, click_y}) do
      start_file_nav_resize(scene)
    else
      handle_regular_left_press(scene, click_x, click_y)
    end
  end

  defp start_file_nav_resize(scene) do
    :ok = capture_input(scene, [:cursor_pos, :cursor_button])

    old_state = scene.assigns.state

    state = %{
      old_state
      | file_nav_resizing: true,
        file_nav_resize_hovered: true,
        file_nav_resize_hide?: false
    }

    graph = QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, state)

    new_scene =
      scene
      |> assign(state: state, graph: graph)
      |> push_graph(graph)

    {:noreply, new_scene}
  end

  defp handle_regular_left_press(scene, click_x, click_y) do
    state = scene.assigns.state
    frame_width = state.frame.size.width

    # --- Icon menu dropdown ---
    # Clicks that are (a) below the top bar AND (b) to the left of the leftmost
    # possible dropdown position are guaranteed to be outside every dropdown.
    # Sending {:close_menu} when the menu is already closed is a harmless no-op.
    dropdown_safe_threshold_x = frame_width - @icon_menu_width - @dropdown_width

    if click_y > @top_bar_height and click_x < dropdown_safe_threshold_x do
      Scenic.Scene.put_child(scene, :icon_menu, {:close_menu})
      # This click is provably outside every dropdown, so no overlay owns
      # the pointer — clear the flag as well, so a lost :dropdown_closed
      # event cannot leave the editor permanently ignoring clicks.
      Scenic.Scene.put_child(scene, :buffer_pane, {:set_overlay_open, false})
    end

    # --- Focus routing between the file nav and the buffer pane ---
    # SideNav and TextField both gate keyboard input on a focus flag; a click
    # decides which of them holds it. Skipped while a dialog is open so a
    # stray click can't pull keyboard focus out from under the dialog.
    scene =
      if click_y > @top_bar_height and not state.show_unsaved_prompt and
           not state.show_nav_delete_prompt and not state.show_about and
           not state.show_shortcuts do
        if side_pane_open?(state) and click_x < state.file_nav_width do
          grant_keyboard(scene, :side_pane)
        else
          grant_keyboard(scene, :buffer)
        end
      else
        scene
      end

    # --- Search bar ---
    # A click does NOT close the find bar. Clicking into the document while a
    # search is up means "let me edit for a moment", not "throw the search
    # away" — the query, the match count and the place in the results are all
    # still wanted, and retyping them because a hand slipped is the annoying
    # part of every editor that does close it. Escape closes it, and so does
    # the bar's own X.
    {:noreply, scene}
  end

  # Mouse clicks on child components (TextField, IconMenu, FilePicker, etc.) are
  # handled by those components via Scenic's hit-testing and their own
  # request_input registrations.  This catch-all handles any remaining events.
  def handle_input(_input, _context, scene) do
    {:noreply, scene}
  end

  defp adjust_chrome_zoom(delta) do
    current = Quillex.RadixCache.ViewStore.get_state().chrome_zoom
    Quillex.RadixCache.ViewStore.set_chrome_zoom(min(200, max(50, current + delta)))
  end

  defp update_file_nav_resize_hover(scene, coords, hovered?) do
    old_state = scene.assigns.state
    new_state = %{old_state | cursor_pos: coords, file_nav_resize_hovered: hovered?}

    if old_state.file_nav_resize_hovered == hovered? do
      {:noreply, assign(scene, state: new_state)}
    else
      new_graph =
        QuillEx.RootScene.Renderizer.render(
          scene.assigns.graph,
          scene,
          old_state,
          new_state
        )

      new_scene =
        scene
        |> assign(state: new_state, graph: new_graph)
        |> push_graph(new_graph)

      {:noreply, new_scene}
    end
  end

  defp file_nav_resize_handle_hit?(scene, {x, y}) do
    state = scene.assigns.state
    content_height = state.frame.size.height - @top_bar_height
    center_y = @top_bar_height + content_height * 0.9

    side_pane_open?(state) and abs(x - state.file_nav_width) <= 16 and
      abs(y - center_y) <= 26
  end

  # IconMenu only receives positional motion while Scenic considers one of its
  # primitives the target. Relay the one transition it otherwise cannot see:
  # leaving its parent-owned frame for a sibling component.
  defp maybe_clear_icon_menu_hover(scene, previous_coords, coords) do
    if icon_menu_point?(scene, previous_coords) and not icon_menu_point?(scene, coords) do
      Scenic.Scene.put_child(scene, :icon_menu, :clear_hover)
    end

    :ok
  end

  defp icon_menu_point?(_scene, nil), do: false

  defp icon_menu_point?(scene, {x, y}) do
    width = scene.assigns.state.frame.size.width
    x >= width - @icon_menu_width and x <= width and y >= 0 and y <= @top_bar_height
  end

  # Dispatch a single buffer action to the currently active buffer.
  # Calls the Buffer.Process synchronously, then pushes the resulting state
  # to the BufferPane (TextField) for an immediate UI update.  Also updates
  # the dirty indicator in the tab bar.  When no buffer is active (e.g. during
  # startup) the call is silently ignored and the scene is returned unchanged.
  # Compute how many lines fit in the visible buffer area.
  # Uses the current viewport frame height, subtracts the top bar, and divides
  # by the buffer line height. Falls back to 20 if the frame is not yet set.
  # The very last position in the active document.
  defp document_end(scene) do
    {:ok, snapshot} = Quillex.Buffer.fetch(scene.assigns.state.active_buf)
    line = length(snapshot.lines)
    {line, String.length(Enum.at(snapshot.lines, line - 1, "")) + 1}
  end

  defp compute_page_size(scene) do
    case scene.assigns.state.frame do
      nil -> 20
      frame -> max(1, div(trunc(frame.size.height) - @top_bar_height, @line_height))
    end
  end

  defp dispatch_to_active_buffer(scene, action) do
    state = scene.assigns.state

    cond do
      # An overlay owns the keyboard: these shortcuts edit/move within the
      # DOCUMENT, and firing them while the user is typing in the search bar
      # or answering a dialog mutates the file behind their back (Ctrl+D
      # would delete a line of the document mid-search).
      state.show_goto_line or
        state.show_search_bar or state.show_unsaved_prompt or
        state.show_nav_delete_prompt or
        Map.get(state, :show_about, false) or Map.get(state, :show_shortcuts, false) or
          state.show_file_picker ->
        {:noreply, scene}

      true ->
        do_dispatch_to_active_buffer(scene, action)
    end
  end

  defp keyboard_overlay_open?(state) do
    state.show_goto_line or
      state.show_search_bar or state.show_unsaved_prompt or state.show_file_picker or
      state.show_nav_delete_prompt or state.show_save_settings_prompt or
      Map.get(state, :show_about, false) or Map.get(state, :show_shortcuts, false)
  end

  defp do_dispatch_to_active_buffer(scene, action) do
    case scene.assigns.state.active_buf do
      nil ->
        {:noreply, scene}

      buf_ref ->
        # Synchronous so keyboard-shortcut ordering is deterministic; the
        # TextField updates via the buffer's publish -> PaneStore republish
        # (no direct state push needed).
        {:ok, new_buf} = Quillex.Buffer.BufferManager.call_buffer(buf_ref, {:action, action})

        # Reflect any dirty change in the tab bar.
        scene = maybe_update_dirty_state(scene, new_buf)

        {:noreply, scene}
    end
  end

  # Get the cursor position from the active buffer (Buffer.Process is source of truth)
  defp get_buffer_cursor(scene) do
    with buf_ref when not is_nil(buf_ref) <- scene.assigns.state.active_buf,
         {:ok, buf_state} <- Quillex.Buffer.Process.fetch_buf(buf_ref),
         %{line: line, col: col} <- buf_state.cursor do
      {line, col}
    else
      _ -> nil
    end
  end

  # Scroll position is now preserved by the pane itself (it survives layout
  # changes instead of being recreated), so nothing needs to read it back
  # out of the component. Kept only for the initial-creation path.
  #
  # It must NOT be called on the hot path: fetch_child blocks on whatever
  # the component is currently rendering, and on a large document that is
  # long enough to time out and crash the scene.
  defp get_first_visible_line(scene) do
    alias ScenicWidgets.TextField.State, as: TFState

    try do
      case Scenic.Scene.fetch_child(scene, :buffer_pane) do
        {:ok, [%TFState{scroll: scroll, font: font} = _tf_state]} ->
          line_height = font.size
          # Calculate which source line is at the top of the viewport
          # offset_y is how far we've scrolled down in pixels
          first_line = max(1, trunc(scroll.offset_y / line_height) + 1)
          first_line

        _ ->
          nil
      end
    catch
      :exit, _ -> nil
    end
  end

  def handle_call(:get_active_buffer, _from, scene) do
    {:reply, {:ok, scene.assigns.state.active_buf}, scene}
  end

  def handle_call(:get_state, _from, scene) do
    {:reply, {:ok, scene.assigns.state}, scene}
  end

  # Editor-settings toggles are ViewStore dispatches; the scene re-renders
  # (via the update_editor_settings flow) when the :radix_view snapshot lands
  def handle_call({:action, [toggle]}, _from, scene)
      when toggle in [:toggle_line_numbers, :toggle_word_wrap, :toggle_file_nav] do
    dispatch_toggle(toggle)
    {:reply, :ok, scene}
  end

  # NOTE: file opening goes through Quillex.API.FileAPI.open/1 (see open_file/2
  # below and Quillex.TestHelpers.FileOpener) — there is deliberately no
  # {:open_file, path} action clause here.
  def handle_call({:action, actions}, _from, scene) when is_list(actions) do
    case apply_scene_actions(scene, actions) do
      {:ok, new_scene} -> {:reply, :ok, new_scene}
      {:error, reason} -> {:reply, {:error, reason}, scene}
    end
  end

  def handle_call({:action, a}, _from, scene) do
    # wrap singular actions in a list and push through the multi-action pipeline anyway
    handle_call({:action, [a]}, nil, scene)
  end

  # The single reduce → render → push path shared by the call and cast
  # {:action, actions} entry points.
  #
  # On {:error, _} the scene is left untouched rather than crashed. This can
  # mask a race: e.g. an {:activate_buffer, ref} action arriving before the
  # BufferManager's :new_buffer_opened broadcast has added the buffer to scene
  # state. See the retry/acknowledgement ideas in the git history if this
  # needs to become robust.
  defp apply_scene_actions(scene, actions) do
    case process_actions(scene, actions) do
      {:ok, {new_state, new_graph}} ->
        new_scene =
          scene
          |> assign(state: new_state)
          |> assign(graph: new_graph)
          |> push_graph(new_graph)

        {:ok, new_scene}

      {:error, reason} ->
        Logger.warning("Couldn't compute action #{inspect(actions)}. #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_actions(scene, actions) do
    # wormhole will wrap this function in an ok/error tuple even if it crashes
    Wormhole.capture(fn ->
      old_state = scene.assigns.state

      new_state = Enum.reduce(actions, old_state, &RootScene.Reducer.process(&2, &1))

      # Reuse existing graph to preserve component PIDs and avoid race conditions
      # during rapid buffer switches. Pass old_state to enable smart component updates
      # (only recreate when truly necessary, like switching buffers).
      new_graph =
        QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

      {new_state, new_graph}
    end)
  end

  # Editor-settings toggles are ViewStore dispatches; the scene re-renders
  # (via the update_editor_settings flow) when the :radix_view snapshot lands
  def handle_cast({:action, [toggle]}, scene)
      when toggle in [:toggle_line_numbers, :toggle_word_wrap, :toggle_file_nav] do
    dispatch_toggle(toggle)
    {:noreply, scene}
  end

  defp dispatch_toggle(:toggle_line_numbers),
    do: Quillex.RadixCache.ViewStore.toggle_line_numbers()

  defp dispatch_toggle(:toggle_word_wrap), do: Quillex.RadixCache.ViewStore.toggle_word_wrap()
  defp dispatch_toggle(:toggle_file_nav), do: Quillex.RadixCache.ViewStore.toggle_file_nav()

  # Buffer-list actions are store dispatches: BufferManager owns that state,
  # and the scene re-renders when the :radix_buffers snapshot arrives.
  def handle_cast({:action, {:activate_buffer, x}}, scene) do
    Quillex.Buffer.BufferManager.activate_buffer(x)
    {:noreply, scene}
  end

  def handle_cast({:action, {:close_buffer, %Quillex.Buffer.Ref{} = buf_ref}}, scene) do
    Quillex.Buffer.BufferManager.close_buffer(buf_ref)
    {:noreply, scene}
  end

  def handle_cast({:action, :run_verification}, scene) do
    # Access active buffer directly from scene state to avoid a GenServer.call deadlock.
    # FileAPI.verify_file_integrity() goes through Buffer.active_buf() which calls
    # GenServer.call(QuillEx.RootScene, :get_active_buffer) — a self-call that deadlocks
    # because run_verification is always invoked from within the RootScene GenServer.
    # Instead, read buf_ref from scene assigns and call Buffer.Process.fetch_buf/1 directly
    # (which calls the separate Buffer.Process GenServer, not RootScene — no deadlock).
    case scene.assigns.state.active_buf do
      nil ->
        Logger.info("[run_verification] No active buffer")
        {:noreply, scene}

      buf_ref ->
        # Wrap fetch_buf in try/catch: call_buffer/2 raises (rather than returning
        # {:error, ...}) when the buffer process is not found in the Registry.
        # This can happen if the buffer crashes between the active_buf check and
        # this call, or in test environments where no Registry is running.
        buf_result =
          try do
            Quillex.Buffer.Process.fetch_buf(buf_ref)
          rescue
            e -> {:error, Exception.message(e)}
          catch
            :exit, reason -> {:error, "buffer process exited: #{inspect(reason)}"}
          end

        case buf_result do
          {:ok, %Quillex.Structs.BufState{source: %{filepath: file_path}, data: buf_data}}
          when is_binary(file_path) ->
            # Delegate comparison to the canonical implementation in FileAPI so
            # the file-reading + line-splitting logic lives in exactly one place.
            case Quillex.API.FileAPI.check_file_status(buf_data, file_path) do
              {:ok, :unchanged} ->
                Logger.info("[run_verification] File is unchanged on disk")
                show_status(scene, "File is unchanged on disk", :info)

              {:ok, :modified} ->
                Logger.warning(
                  "[run_verification] File has been modified on disk since last save"
                )

                show_status(scene, "File has been modified on disk since last save", :warning)

              {:ok, :deleted} ->
                Logger.warning("[run_verification] File has been deleted from disk")
                show_status(scene, "File has been deleted from disk", :warning)

              {:error, reason} ->
                Logger.warning("[run_verification] Failed to read file: #{reason}")
                show_status(scene, "Failed to read file: #{reason}", :warning)
            end

          {:ok, %Quillex.Structs.BufState{}} ->
            Logger.info("[run_verification] Buffer has no associated file path")
            show_status(scene, "Buffer has no associated file path", :info)

          {:error, reason} ->
            Logger.debug(
              "[run_verification] Skipped (failed to fetch buffer state): #{inspect(reason)}"
            )

            {:noreply, scene}
        end
    end
  end

  def handle_cast({:action, :reload_from_disk}, scene) do
    # Reload the active buffer's content from its associated file on disk.
    #
    # Uses the same deadlock-safe pattern as run_verification: read buf_ref
    # directly from scene assigns rather than calling Buffer.active_buf(), which
    # routes through RootScene GenServer and would cause a self-call deadlock.
    case scene.assigns.state.active_buf do
      nil ->
        Logger.info("[reload_from_disk] No active buffer")
        {:noreply, scene}

      buf_ref ->
        buf_result =
          try do
            Quillex.Buffer.Process.fetch_buf(buf_ref)
          rescue
            e -> {:error, Exception.message(e)}
          catch
            :exit, reason -> {:error, "buffer process exited: #{inspect(reason)}"}
          end

        case buf_result do
          {:ok, %Quillex.Structs.BufState{source: %{filepath: file_path}}}
          when is_binary(file_path) ->
            case File.read(file_path) do
              {:ok, content} ->
                new_lines = String.split(content, "\n")
                # Apply set_data + set_cursor + mark_clean as a single atomic list
                # so the buffer process broadcasts one :buf_state_changes event.
                Quillex.Buffer.BufferManager.call_buffer(
                  buf_ref,
                  {:action, [{:set_data, new_lines}, {:set_cursor, {1, 1}}, :mark_clean]}
                )

                Logger.info(
                  "[reload_from_disk] Reloaded #{length(new_lines)} lines from #{file_path}"
                )

                show_status(scene, "File reloaded from disk", :info)

              {:error, :enoent} ->
                Logger.warning("[reload_from_disk] File has been deleted from disk")
                show_status(scene, "Cannot reload: file has been deleted from disk", :warning)

              {:error, reason} ->
                Logger.warning("[reload_from_disk] Failed to read file: #{reason}")
                show_status(scene, "Failed to reload file: #{reason}", :warning)
            end

          {:ok, %Quillex.Structs.BufState{}} ->
            Logger.info("[reload_from_disk] Buffer has no associated file path")
            show_status(scene, "Buffer has no associated file path", :info)

          {:error, reason} ->
            Logger.debug(
              "[reload_from_disk] Skipped (failed to fetch buffer state): #{inspect(reason)}"
            )

            {:noreply, scene}
        end
    end
  end

  def handle_cast({:action, actions}, scene) when is_list(actions) do
    case apply_scene_actions(scene, actions) do
      {:ok, new_scene} -> {:noreply, new_scene}
      {:error, _reason} -> {:noreply, scene}
    end
  end

  def handle_cast({:action, a}, scene) do
    # wrap singular actions in a list and push through the multi-action pipeline anyway
    handle_cast({:action, [a]}, scene)
  end

  # Handle file picker events
  def handle_cast({:file_picker, :file_selected, path}, scene) do
    hide_file_picker(scene, path)
  end

  def handle_cast({:file_picker, :file_saved, path}, scene) do
    hide_file_picker_and_save(scene, path)
  end

  def handle_cast({:file_picker, :cancelled}, scene) do
    hide_file_picker(scene)
  end

  # ===========================================================================
  # SearchBar events (via cast_parent)
  # ===========================================================================

  def handle_cast({:search_query_changed, _id, query}, scene) do
    Logger.debug("[search] query changed: #{inspect(query)}")

    new_state = %{scene.assigns.state | search_query: query}

    # Perform the search if query is not empty
    if String.length(query) > 0 do
      perform_search(scene, query, new_state)
    else
      # Clear search results
      new_state = %{new_state | search_current_match: 0, search_total_matches: 0}
      Scenic.Scene.put_child(scene, :buffer_pane, {:action, :clear_search})
      new_scene = scene |> assign(state: new_state)
      {:noreply, new_scene}
    end
  end

  # Match Case or Use Regular Expression was toggled in the find bar. The same
  # query means something different now, so it has to run again.
  def handle_cast({:search_options_changed, _id, opts}, scene) do
    state = %{scene.assigns.state | search_opts: opts}

    if state.search_query == "" do
      {:noreply, assign(scene, state: state)}
    else
      perform_search(scene, state.search_query, state)
    end
  end

  def handle_cast({:search_next, _id}, scene) do
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, :find_next})
    {:noreply, scene}
  end

  def handle_cast({:search_prev, _id}, scene) do
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, :find_prev})
    {:noreply, scene}
  end

  # Undo and redo asked for from the find bar. They act on the DOCUMENT: the
  # bar's own fields hold a query, not work worth keeping, and the thing you
  # want back after a replace is the text.
  def handle_cast({:undo_requested, _id}, scene),
    do: do_dispatch_to_active_buffer(scene, :undo)

  def handle_cast({:redo_requested, _id}, scene),
    do: do_dispatch_to_active_buffer(scene, :redo)

  def handle_cast({:search_close, _id}, scene) do
    hide_search_bar(scene)
  end

  # Ctrl+H pressed inside the (focused) search bar: grow it into replace mode.
  def handle_cast({:replace_mode_requested, _id}, scene) do
    show_search_bar(scene, replace_mode: true)
  end

  # The bar's disclosure caret. Unlike Ctrl+H, which only ever opens the
  # replacement row, this closes it again — a caret that cannot put back what
  # it revealed is a button that does nothing every second time it is pressed.
  def handle_cast({:replace_mode_toggled, _id}, scene) do
    if scene.assigns.state.show_replace do
      hide_replace_row(scene)
    else
      show_search_bar(scene, replace_mode: true)
    end
  end

  def handle_cast({:replace_requested, _id, replacement}, scene) do
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, {:replace, replacement}})
    {:noreply, scene}
  end

  # The popup is the BUFFER's find and replace, always. Project-wide replace
  # lives in the pane, which has its own fields — two boxes, two jobs.
  def handle_cast({:replace_all_requested, _id, replacement}, scene) do
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, {:replace_all, replacement}})
    {:noreply, scene}
  end

  # Buffer-list store snapshots (:radix_buffers) — the single path by which
  # the open-buffers list, active buffer, and dirty flags reach the scene.
  def handle_info(
        {{Scenic.PubSub, :data}, {:radix_buffers, %{buffers: buffers, active_buf: active}, _ts}},
        scene
      ) do
    new_state = %{
      scene.assigns.state
      | buffers: buffers,
        active_buf: active,
        preview_buf_uuid: surviving_preview(scene.assigns.state.preview_buf_uuid, buffers)
    }
    new_scene = render_snapshot(scene, new_state)

    if new_state.show_file_nav do
      Scenic.Scene.put_child(new_scene, :file_nav, {:set_active, active && active.path})
    end

    {:noreply, new_scene}
  end

  # View-chrome store snapshots (:radix_view) — editor settings, file nav and
  # status message reach the scene here. Settings/layout changes route through
  # the update_editor_settings flow (cursor + scroll preservation, menu
  # checkmarks); everything else is a plain re-render.
  def handle_info({{Scenic.PubSub, :data}, {:radix_view, view, _ts}}, scene) do
    old_state = scene.assigns.state
    new_state = merge_view(old_state, view)

    result =
      if editor_layout_changed?(old_state, new_state) do
        update_editor_settings(scene, new_state)
      else
        {:noreply, render_snapshot(scene, new_state)}
      end

    case result do
      {:noreply, new_scene} when old_state.file_nav_revision != new_state.file_nav_revision ->
        if new_state.show_file_nav do
          tree = Quillex.Utils.FileTree.build(new_state.file_nav_path || File.cwd!())
          Scenic.Scene.put_child(new_scene, :file_nav, {:update_tree, tree})
        end

        {:noreply, new_scene}

      other ->
        other
    end
  end

  # Project-search store snapshots (:radix_project_search) — scope, options and
  # results. The pane gets a fresh model, nothing else moves.
  def handle_info({{Scenic.PubSub, :data}, {:radix_project_search, snapshot, _ts}}, scene) do
    new_state = %{scene.assigns.state | project_search: snapshot}
    scene = assign(scene, state: new_state)

    if new_state.show_project_search do
      model = Quillex.GUI.SearchPaneModel.build(snapshot)
      Scenic.Scene.put_child(scene, :project_search_pane, {:update_model, model})

    end

    {:noreply, scene}
  end

  # Scenic.PubSub lifecycle notifications — deliberately specific clauses, a
  # catch-all on {{Scenic.PubSub, _}, _} would swallow :data updates.
  def handle_info({{Scenic.PubSub, :registered}, _}, scene), do: {:noreply, scene}
  def handle_info({{Scenic.PubSub, :unregistered}, _}, scene), do: {:noreply, scene}

  # The single render path for store snapshots: diff-render against the
  # previous state, preserving component PIDs where the Renderizer allows.
  defp render_snapshot(scene, new_state) do
    new_graph =
      QuillEx.RootScene.Renderizer.render(
        scene.assigns.graph,
        scene,
        scene.assigns.state,
        new_state
      )

    scene
    |> assign(state: new_state)
    |> assign(graph: new_graph)
    |> push_graph(new_graph)
  end

  # Keys the scene consumes from :radix_view snapshots. Search-bar and dialog
  # flags stay scene-owned until Phase 6b — merging them here would clobber
  # the scene's in-flight dialog state.
  @view_keys [
    :show_line_numbers,
    :show_matching_brace,
    :highlight_current_line,
    :highlight_current_column,
    :word_wrap,
    :auto_indent,
    :tab_width,
    :text_size,
    :fold_level,
    :show_action_feedback,
    :show_menu_shortcuts,
    :chrome_zoom,
    :show_file_nav,
    :file_nav_path,
    :file_nav_width,
    :file_nav_revision,
    :show_project_search,
    :syntax_highlighting,
    :theme,
    :status_message,
    :status_severity
  ]

  defp merge_view(state, view), do: struct(state, Map.take(view, @view_keys))

  defp editor_layout_changed?(old_state, new_state) do
    Enum.any?(
      [
        :show_line_numbers,
        :show_matching_brace,
        :highlight_current_line,
        :highlight_current_column,
        :word_wrap,
        :auto_indent,
        :tab_width,
        :text_size,
        :chrome_zoom,
        :show_file_nav,
        :show_project_search,
        :syntax_highlighting,
        :theme,
        :show_action_feedback
      ],
      fn key -> Map.get(old_state, key) != Map.get(new_state, key) end
    )
  end

  # Handle events from child components (IconMenu, TabBar, etc.)
  def handle_event({:menu_value_changed, "text_size", value}, _from, scene) do
    Quillex.RadixCache.ViewStore.set_text_size(round(value))
    {:noreply, scene}
  end

  def handle_event({:menu_value_changed, "fold_level", value}, _from, scene) do
    level = round(value)
    Quillex.RadixCache.ViewStore.set_fold_level(level)
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, {:fold_to_level, level}})
    {:noreply, scene}
  end

  def handle_event({:menu_value_changed, "tab_width", value}, _from, scene) do
    Quillex.RadixCache.ViewStore.set_tab_width(round(value))
    {:noreply, scene}
  end

  def handle_event({:menu_value_changed, "menu_shortcuts", _checked?}, _from, scene) do
    Quillex.RadixCache.ViewStore.toggle_menu_shortcuts()
    {:noreply, scene}
  end

  def handle_event({:menu_value_changed, "file_nav", _checked?}, _from, scene) do
    Quillex.RadixCache.ViewStore.toggle_file_nav()
    {:noreply, scene}
  end

  def handle_event({:menu_value_changed, "line_numbers", _checked?}, _from, scene) do
    Quillex.RadixCache.ViewStore.toggle_line_numbers()
    {:noreply, scene}
  end

  def handle_event({:menu_value_changed, "matching_brace", _checked?}, _from, scene) do
    Quillex.RadixCache.ViewStore.toggle_matching_brace()
    {:noreply, scene}
  end

  def handle_event({:menu_value_changed, "current_line_highlight", _checked?}, _from, scene) do
    Quillex.RadixCache.ViewStore.toggle_current_line_highlight()
    {:noreply, scene}
  end

  def handle_event({:menu_value_changed, "current_column_highlight", _checked?}, _from, scene) do
    Quillex.RadixCache.ViewStore.toggle_current_column_highlight()
    {:noreply, scene}
  end

  def handle_event({:menu_value_changed, "chrome_zoom", value}, _from, scene) do
    Quillex.RadixCache.ViewStore.set_chrome_zoom(round(value))
    {:noreply, scene}
  end

  def handle_event({:menu_value_changed, "word_wrap", _checked?}, _from, scene) do
    Quillex.RadixCache.ViewStore.toggle_word_wrap()
    {:noreply, scene}
  end

  def handle_event({:menu_value_changed, "action_feedback", _checked?}, _from, scene) do
    Quillex.RadixCache.ViewStore.toggle_action_feedback()
    {:noreply, scene}
  end

  def handle_event({:menu_value_changed, "syntax_highlighting", _checked?}, _from, scene) do
    Quillex.RadixCache.ViewStore.toggle_syntax_highlighting()
    {:noreply, scene}
  end

  def handle_event({:menu_item_clicked, item_id}, _from, scene) do
    Logger.debug("Menu item clicked: #{inspect(item_id)}")

    # Choosing an item always dismisses the dropdown, so clear the pane's
    # "an overlay owns the pointer" flag here too. Relying solely on the
    # separate :dropdown_closed event makes a single lost message latch the
    # flag on — and while it is on, EVERY click on the editor is ignored.
    Scenic.Scene.put_child(scene, :buffer_pane, {:set_overlay_open, false})

    case item_id do
      "new" ->
        # Create a new buffer
        handle_cast({:action, :new_buffer}, scene)

      "open" ->
        # Show the file picker modal
        show_file_picker(scene)

      "save" ->
        do_save(scene)

      "save_as" ->
        # Show file picker in save mode
        show_file_picker_save(scene)

      "verify" ->
        # Run file verification
        handle_cast({:action, :run_verification}, scene)

      "reload" ->
        # Reload buffer content from disk
        handle_cast({:action, :reload_from_disk}, scene)

      "close" ->
        # Close the active buffer — show unsaved-changes dialog if buffer is dirty.
        try_close_active_buffer(scene)

      "undo" ->
        # Undo - send undo action to the buffer pane
        Scenic.Scene.put_child(scene, :buffer_pane, {:action, :undo})
        {:noreply, scene}

      "redo" ->
        # Redo - send redo action to the buffer pane
        Scenic.Scene.put_child(scene, :buffer_pane, {:action, :redo})
        {:noreply, scene}

      "cut" ->
        Scenic.Scene.put_child(scene, :buffer_pane, {:action, {:cut, :selection}})
        {:noreply, scene}

      "copy" ->
        Scenic.Scene.put_child(scene, :buffer_pane, {:action, {:copy, :selection}})
        {:noreply, scene}

      "paste" ->
        Scenic.Scene.put_child(scene, :buffer_pane, {:action, {:paste, :at_cursor}})
        {:noreply, scene}

      "select_all" ->
        Scenic.Scene.put_child(scene, :buffer_pane, {:action, :select_all})
        {:noreply, scene}

      "delete_line" ->
        Scenic.Scene.put_child(scene, :buffer_pane, {:action, :delete_line})
        {:noreply, scene}

      "find" ->
        # Find - show search bar
        show_search_bar(scene)

      "find_replace" ->
        # Find & Replace - show search bar with replace row
        show_search_bar(scene, replace_mode: true)

      "find_next" ->
        # Find next match
        Scenic.Scene.put_child(scene, :buffer_pane, {:action, :find_next})
        {:noreply, scene}

      "goto_line" ->
        show_goto_line(scene)

      "find_in_project" ->
        open_project_search(scene, focus: :query)

      "replace_in_project" ->
        open_project_search(scene, focus: :replace)

      "file_nav" ->
        Quillex.RadixCache.ViewStore.toggle_file_nav()
        {:noreply, scene}

      "line_numbers" ->
        Quillex.RadixCache.ViewStore.toggle_line_numbers()
        {:noreply, scene}

      "auto_indent" ->
        Quillex.RadixCache.ViewStore.toggle_auto_indent()
        {:noreply, scene}

      "word_wrap" ->
        Quillex.RadixCache.ViewStore.toggle_word_wrap()
        {:noreply, scene}

      "action_feedback" ->
        Quillex.RadixCache.ViewStore.toggle_action_feedback()
        {:noreply, scene}

      # Theme radio rows. One palette drives the editor and every piece of
      # chrome, so this is the only place a colour scheme is chosen.
      "theme_" <> theme ->
        Quillex.RadixCache.ViewStore.set_theme(String.to_existing_atom(theme))
        {:noreply, scene}

      "syntax_highlighting" ->
        Quillex.RadixCache.ViewStore.toggle_syntax_highlighting()
        {:noreply, scene}

      "toggle_fold" ->
        {line, _col} = get_buffer_cursor(scene) || {1, 1}
        Scenic.Scene.put_child(scene, :buffer_pane, {:action, {:toggle_fold, line}})
        {:noreply, scene}

      "unfold_all" ->
        Scenic.Scene.put_child(scene, :buffer_pane, {:action, :unfold_all})
        {:noreply, scene}

      "fold_level_" <> level when level in ["1", "2", "3", "4"] ->
        Scenic.Scene.put_child(
          scene,
          :buffer_pane,
          {:action, {:fold_to_level, String.to_integer(level)}}
        )

        {:noreply, scene}

      "save_default_settings" ->
        show_save_settings_dialog(scene)

      # No settings dialog, no schema, no persistence layer: the list of
      # things a search skips is a text file, and this application opens text
      # files. Editing it and saving is the whole workflow, and the next
      # search reads it back.
      "edit_search_excludes" ->
        # Asking for the patterns writes the file with its defaults if it is
        # not there yet, so there is always something to open and read.
        _ = Quillex.Search.Excludes.patterns()
        {:ok, _} = Quillex.API.FileAPI.open(Quillex.Search.Excludes.path())
        {:noreply, scene}

      "about" ->
        show_about_dialog(scene)

      "shortcuts" ->
        show_shortcuts_dialog(scene)

      _other ->
        Logger.warning("Unknown menu item: #{inspect(item_id)}")
        {:noreply, scene}
    end
  end

  # Handle tab selection from TabBar
  def handle_event({:tab_selected, tab_id}, _from, scene) do
    Logger.debug("Tab selected: #{inspect(tab_id)}")

    # Find the buffer with this UUID and activate it
    buf_ref = Enum.find(scene.assigns.state.buffers, fn buf -> buf.uuid == tab_id end)

    if buf_ref do
      # With store_backed mode, Buffer.Process is source of truth - no sync needed
      handle_cast({:action, {:activate_buffer, buf_ref}}, scene)
    else
      Logger.warning("Could not find buffer for tab: #{inspect(tab_id)}")
      {:noreply, scene}
    end
  end

  # Double-clicking a preview tab keeps it: the gesture every editor uses to
  # say "I am staying here", and the counterpart to the next search result
  # otherwise replacing it.
  def handle_event({:tab_double_clicked, tab_id}, _from, scene) do
    {:noreply, promote_preview(scene, tab_id)}
  end

  def handle_event({:tabs_reordered, tab_ids}, _from, scene) do
    Quillex.Buffer.BufferManager.reorder_buffers(tab_ids)
    {:noreply, scene}
  end

  # Handle tab close from TabBar
  def handle_event({:tab_closed, tab_id}, _from, scene) do
    Logger.debug("Tab close requested: #{inspect(tab_id)}")

    # Find the buffer with this UUID and close it
    buf_ref = Enum.find(scene.assigns.state.buffers, fn buf -> buf.uuid == tab_id end)

    if buf_ref do
      # With store_backed mode, Buffer.Process is source of truth — show
      # unsaved-changes dialog if dirty, otherwise close immediately.
      try_close_buffer(scene, buf_ref)
    else
      Logger.warning("Could not find buffer for tab close: #{inspect(tab_id)}")
      {:noreply, scene}
    end
  end

  # Save file (Ctrl+S from TextField)
  def handle_event({:save_requested, _id, _text}, _from, scene) do
    # With store_backed mode, Buffer.Process already has current content - no sync needed
    do_save(scene)
  end

  # Find/Search (Ctrl+F from TextField)
  def handle_event({:find_requested, _id}, _from, scene) do
    show_search_bar(scene)
  end

  # Find & Replace (Ctrl+H from TextField)
  def handle_event({:replace_mode_requested, _id}, _from, scene) do
    show_search_bar(scene, replace_mode: true)
  end

  # Go to Line (Ctrl+G from TextField)
  def handle_event({:goto_line_requested, _id}, _from, scene), do: show_goto_line(scene)

  # ── Go to Line ────────────────────────────────────────────────────────────
  #
  # The prompt takes digits only, so RootScene collects them itself instead of
  # hosting an editable text field. Keystrokes reach here because the modal
  # blurs the buffer pane, and `keyboard_overlay_open?/1` keeps document
  # shortcuts from firing underneath.

  defp show_goto_line(%{assigns: %{state: %{show_goto_line: true}}} = scene),
    do: {:noreply, scene}

  defp show_goto_line(scene) do
    state = scene.assigns.state
    new_state = %{state | show_goto_line: true, goto_line_input: ""}

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: goto_line_graph(scene.assigns.graph, new_state))
      |> then(&(&1 |> push_graph(&1.assigns.graph)))

    Scenic.Scene.put_child(new_scene, :buffer_pane, :blur)
    {:noreply, new_scene}
  end

  defp goto_line_graph(graph, state) do
    typed = state.goto_line_input
    total = length(active_buffer_lines(state))

    graph
    |> Scenic.Graph.delete(:goto_line_prompt)
    |> ScenicWidgets.PopupModal.add_to_graph(
      %{
        frame: state.frame,
        title: "Go to Line",
        body: [
          "Line number:  #{if typed == "", do: "_", else: typed}",
          "",
          "1 - #{total}      Enter to jump, Escape to cancel"
        ]
      },
      id: :goto_line_prompt
    )
  end

  defp hide_goto_line(scene) do
    state = %{scene.assigns.state | show_goto_line: false, goto_line_input: ""}
    graph = Scenic.Graph.delete(scene.assigns.graph, :goto_line_prompt)

    new_scene = scene |> assign(state: state) |> assign(graph: graph) |> push_graph(graph)
    Scenic.Scene.put_child(new_scene, :buffer_pane, :focus)
    new_scene
  end

  defp active_buffer_lines(%{active_buf: nil}), do: []

  defp active_buffer_lines(%{active_buf: buf_ref}) do
    case Quillex.Buffer.fetch(buf_ref) do
      {:ok, %{lines: lines}} -> lines
      _ -> []
    end
  end

  defp update_goto_line(scene, typed) do
    new_state = %{scene.assigns.state | goto_line_input: typed}
    graph = goto_line_graph(scene.assigns.graph, new_state)
    scene |> assign(state: new_state) |> assign(graph: graph) |> push_graph(graph)
  end

  # Number-row and keypad digits both, since a line number is exactly what a
  # numeric keypad is for.
  defp goto_line_digit(key) do
    case Atom.to_string(key) do
      "key_" <> <<d>> when d in ?0..?9 -> <<d>>
      "key_kp_" <> <<d>> when d in ?0..?9 -> <<d>>
      _ -> nil
    end
  end

  defp commit_goto_line(scene) do
    state = scene.assigns.state
    lines = active_buffer_lines(state)
    scene = hide_goto_line(scene)

    case Integer.parse(state.goto_line_input) do
      {n, ""} when n >= 1 and lines != [] ->
        # Clamp rather than refuse. 999999 is what people type when they mean
        # "the end", and an editor that answers that with an error is being
        # pedantic at the user's expense.
        line = min(n, length(lines))
        Scenic.Scene.put_child(scene, :buffer_pane, {:action, {:set_cursor, {line, 1}}})
        Quillex.RadixCache.ViewStore.show_status("Line #{line}", :info)
        {:noreply, scene}

      _ ->
        {:noreply, scene}
    end
  end

  # NOTE: SearchBar communicates via cast_parent/2, so search/replace UI events
  # arrive as handle_cast — see the "Search bar" handle_cast clauses above.
  # TextField communicates via send_parent_event, handled below.

  # Search complete (from TextField after parallel search)
  def handle_event({:search_complete, _id, query, match_count}, _from, scene) do
    Logger.debug("[search] #{match_count} matches for #{inspect(query)}")

    # Update state with match count
    new_state = %{
      scene.assigns.state
      | search_total_matches: match_count,
        search_current_match: if(match_count > 0, do: 1, else: 0)
    }

    # Update the search bar's match count display
    Scenic.Scene.put_child(
      scene,
      :search_bar,
      {:set_matches, new_state.search_current_match, match_count}
    )

    new_scene = scene |> assign(state: new_state)
    {:noreply, new_scene}
  end

  # Search navigation (from TextField on Ctrl+G)
  def handle_event({:search_navigated, _id, current_idx, total}, _from, scene) do
    Logger.debug("[search] navigated to match #{current_idx + 1} of #{total}")

    # Update state and search bar
    new_state = %{scene.assigns.state | search_current_match: current_idx + 1}
    Scenic.Scene.put_child(scene, :search_bar, {:set_matches, current_idx + 1, total})

    new_scene = scene |> assign(state: new_state)
    {:noreply, new_scene}
  end

  # ── SearchPane events ─────────────────────────────────────────────────────
  #
  # The pane owns its fields and its presentation; the scene owns what a search
  # means. Every action it can take is one of these.

  # A pane reporting that a click just gave it the keyboard. Clicks are
  # positional: they arrive at whichever component was under the pointer and
  # never at this scene, so this event is the only way it learns that focus
  # moved. Its job is to take the keyboard off everyone else.
  def handle_event({:focus_taken, :buffer_pane}, _from, scene) do
    {:noreply, grant_keyboard(scene, :buffer)}
  end

  def handle_event({:focus_taken, pane}, _from, scene)
      when pane in [:project_search_pane, :file_nav] do
    {:noreply, grant_keyboard(scene, :side_pane)}
  end

  def handle_event({:focus_taken, _other}, _from, scene), do: {:noreply, scene}

  def handle_event({:search_pane, :close}, _from, scene) do
    Quillex.RadixCache.ViewStore.close_project_search()
    {:noreply, grant_keyboard(scene, :buffer)}
  end

  def handle_event({:search_pane, :query_changed, query}, _from, scene) do
    Quillex.RadixCache.ProjectSearchStore.set_query(query)
    {:noreply, assign(scene, state: %{scene.assigns.state | project_search_query: query})}
  end

  def handle_event({:search_pane, :set_results_view, which}, _from, scene) do
    Quillex.RadixCache.ViewStore.set_search_results_view(which)

    # And show it now. The pane's model is built from the SEARCH snapshot, and
    # this setting lives in the view store — without pushing a fresh model the
    # slider would not move until the next search happened to publish one.
    if scene.assigns.state.show_project_search do
      model =
        scene.assigns.state
        |> QuillEx.RootScene.Renderizer.project_search_snapshot()
        |> Quillex.GUI.SearchPaneModel.build()
        |> Map.put(:results_view, which)

      Scenic.Scene.put_child(scene, :project_search_pane, {:update_model, model})
    end

    {:noreply, scene}
  end

  def handle_event({:search_pane, :clear}, _from, scene) do
    Quillex.RadixCache.ProjectSearchStore.set_query("")
    Scenic.Scene.put_child(scene, :project_search_pane, {:set_query, ""})
    {:noreply, scene}
  end

  # The exclude list is a file, and this is a text editor: opening it IS the
  # settings UI. Reached from the pane rather than a menu, beside the switch
  # that says whether it is being honoured.
  def handle_event({:search_pane, :edit_excludes}, _from, scene) do
    _ = Quillex.Search.Excludes.patterns()
    {:ok, _} = Quillex.API.FileAPI.open(Quillex.Search.Excludes.path())
    {:noreply, scene}
  end

  # "Replace" in a project search means the first match still standing. There
  # is no cursor here — the results are a list, not a position — so pressing
  # it repeatedly walks down them, which is the reviewable way to do a
  # replace you are not sure about.
  def handle_event({:search_pane, :replace_one, replacement}, _from, scene) do
    case Quillex.RadixCache.ProjectSearchStore.get_state().files do
      [{path, [match | _]} | _] ->
        Quillex.RadixCache.ProjectSearchStore.replace_match(
          path,
          match.line,
          match.col,
          replacement
        )

      _ ->
        :ok
    end

    {:noreply, scene}
  end

  def handle_event({:search_pane, :toggle_option, option}, _from, scene) do
    Quillex.RadixCache.ProjectSearchStore.toggle_option(option)
    {:noreply, scene}
  end

  def handle_event({:search_pane, :toggle_scope, dir}, _from, scene) do
    Quillex.RadixCache.ProjectSearchStore.toggle_scope(dir)
    {:noreply, scene}
  end

  def handle_event({:search_pane, :open_match, path, line, col}, _from, scene) do
    open_preview_at(scene, path, {line, col})
  end

  def handle_event({:search_pane, :dismiss_match, path, line, col}, _from, scene) do
    Quillex.RadixCache.ProjectSearchStore.dismiss_match(path, line, col)
    {:noreply, scene}
  end

  def handle_event({:search_pane, :dismiss_file, path}, _from, scene) do
    Quillex.RadixCache.ProjectSearchStore.dismiss_file(path)
    {:noreply, scene}
  end

  def handle_event({:search_pane, :replace_match, path, line, col, replacement}, _from, scene) do
    Quillex.RadixCache.ProjectSearchStore.replace_match(path, line, col, replacement)
    {:noreply, scene}
  end

  def handle_event({:search_pane, :replace_file, path, replacement}, _from, scene) do
    Quillex.RadixCache.ProjectSearchStore.replace_file(path, replacement)
    {:noreply, scene}
  end

  def handle_event({:search_pane, :replace_all, replacement}, _from, scene) do
    Quillex.RadixCache.ProjectSearchStore.replace_all(replacement)
    {:noreply, scene}
  end

  # Handle file navigation from SideNav (file explorer sidebar)
  def handle_event({:sidebar, :navigate, item_id}, _from, scene) when is_binary(item_id) do
    # item_id is the file path
    if File.regular?(item_id) do
      Logger.info("File nav: opening file #{item_id}")
      # Opening a file moves the user's attention to the editor: hand keyboard
      # focus back so they can type immediately (and the nav stops eating keys).
      open_file(grant_keyboard(scene, :buffer), item_id)
    else
      Logger.debug("File nav: not a regular file: #{item_id}")
      {:noreply, scene}
    end
  end

  # Handle expand/collapse events from SideNav (informational only)
  def handle_event({:sidebar, :expand, _item_id}, _from, scene), do: {:noreply, scene}
  def handle_event({:sidebar, :collapse, _item_id}, _from, scene), do: {:noreply, scene}
  def handle_event({:sidebar, :hover, _item_id}, _from, scene), do: {:noreply, scene}

  def handle_event({:sidebar, :move_requested, paths, target}, _from, scene) do
    case Quillex.Files.NavigatorOps.move(paths, target) do
      {:ok, moves} ->
        Quillex.RadixCache.ViewStore.show_status(
          "Moved #{length(moves)} #{entry_word(length(moves))} to #{Path.basename(target)}",
          :info
        )

      {:error, reason} ->
        Quillex.RadixCache.ViewStore.show_status(
          "Move failed: #{format_nav_error(reason)}",
          :error
        )
    end

    {:noreply, scene}
  end

  def handle_event({:sidebar, :rename_requested, path, new_name}, _from, scene) do
    case Quillex.Files.NavigatorOps.rename(path, new_name) do
      {:ok, {_old_path, new_path}} ->
        Quillex.RadixCache.ViewStore.show_status(
          "Renamed to #{Path.basename(new_path)}",
          :info
        )

      {:error, reason} ->
        Quillex.RadixCache.ViewStore.show_status(
          "Rename failed: #{format_nav_error(reason)}",
          :error
        )
    end

    {:noreply, scene}
  end

  def handle_event({:sidebar, :delete_requested, []}, _from, scene), do: {:noreply, scene}

  def handle_event({:sidebar, :delete_requested, paths}, _from, scene) do
    state = scene.assigns.state
    count = length(paths)

    graph =
      scene.assigns.graph
      |> ScenicWidgets.ConfirmDialog.add_to_graph(
        %{
          frame: state.frame,
          title: "Delete #{count} #{entry_word(count)}?",
          message: "This permanently deletes the selected files and directories.",
          buttons: [{:discard, "Delete"}, {:cancel, "Cancel"}]
        },
        id: :nav_delete_prompt
      )

    new_state = %{state | pending_nav_delete: paths, show_nav_delete_prompt: true}

    new_scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    Scenic.Scene.put_child(new_scene, :buffer_pane, :blur)
    {:noreply, new_scene}
  end

  # ===========================================================================
  # Unsaved-changes dialog responses
  # ===========================================================================
  #
  # The ConfirmDialog component sends {:confirm_dialog_response, id, action}
  # to its parent (this scene) when the user clicks a button or presses a
  # keyboard shortcut (s = save, d = discard, Escape = cancel).
  #
  # :save   — write the buffer to disk, then close it.
  #           NOTE: for buffers that have no filepath yet (new, unsaved files),
  #           do_save/1 will open the file-picker in save mode. In that case the
  #           close is deferred — the user must close again after choosing a path.
  #           This is a known v1 limitation; a seamless "save-then-close" for new
  #           files requires chained state machines and is left for a later cycle.
  # :discard — close without saving (changes are lost).
  # :cancel  — leave the buffer open with its unsaved changes intact.

  # --- Save Settings as Default ---
  #
  # Every other editor writes your preferences back the moment you change one,
  # which is fine until you widen the tabs to read somebody else's file and
  # find the wide tabs waiting for you tomorrow. Here, changing a setting
  # changes this session; making it permanent is this, and it says so first.
  defp show_save_settings_dialog(scene) do
    state = scene.assigns.state

    graph =
      scene.assigns.graph
      |> ScenicWidgets.ConfirmDialog.add_to_graph(
        %{
          frame: state.frame,
          title: "Save these settings as the default?",
          message:
            "Every new session will start with the settings you have now — " <>
              "theme, tab width, text size, the View menu toggles.\n\n" <>
              "Written to #{Quillex.SettingsFile.path()}.\n\n" <>
              "Nothing is saved until you do this, so changing a setting only " <>
              "ever affects the session you are in.",
          buttons: [{:discard, "Save as Default"}, {:cancel, "Cancel"}]
        },
        id: :save_settings_prompt
      )

    new_state = %{state | show_save_settings_prompt: true}

    new_scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    Scenic.Scene.put_child(new_scene, :buffer_pane, :blur)
    {:noreply, new_scene}
  end

  def handle_event({:confirm_dialog_response, :save_settings_prompt, action}, _from, scene) do
    state = scene.assigns.state
    graph = Scenic.Graph.delete(scene.assigns.graph, :save_settings_prompt)
    new_state = %{state | show_save_settings_prompt: false}

    if action == :discard do
      {:ok, path} = Quillex.SettingsFile.save(Quillex.RadixCache.ViewStore.get_state())
      Quillex.RadixCache.ViewStore.show_status("Saved these settings as default (#{path})", :info)
    end

    new_scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    {:noreply, grant_keyboard(new_scene, :buffer)}
  end

  # --- About dialog ---
  # Any response (OK button, Enter, Escape) just dismisses.
  def handle_event({:popup_modal_response, :about_dialog, _action}, _from, scene) do
    state = scene.assigns.state
    graph = Scenic.Graph.delete(scene.assigns.graph, :about_dialog)

    new_scene =
      scene
      |> assign(state: %{state | show_about: false})
      |> assign(graph: graph)
      |> push_graph(graph)

    Scenic.Scene.put_child(new_scene, :buffer_pane, :focus)
    {:noreply, new_scene}
  end

  def handle_event({:popup_modal_response, :shortcuts_dialog, _action}, _from, scene) do
    state = scene.assigns.state
    graph = Scenic.Graph.delete(scene.assigns.graph, :shortcuts_dialog)

    new_scene =
      scene
      |> assign(state: %{state | show_shortcuts: false})
      |> assign(graph: graph)
      |> push_graph(graph)

    Scenic.Scene.put_child(new_scene, :buffer_pane, :focus)
    {:noreply, new_scene}
  end

  def handle_event({:confirm_dialog_response, :nav_delete_prompt, :discard}, _from, scene) do
    paths = scene.assigns.state.pending_nav_delete

    case Quillex.Files.NavigatorOps.delete(paths) do
      {:ok, deleted} ->
        Quillex.RadixCache.ViewStore.show_status(
          "Deleted #{length(deleted)} #{entry_word(length(deleted))}",
          :info
        )

      {:error, reason} ->
        Quillex.RadixCache.ViewStore.show_status(
          "Delete failed: #{format_nav_error(reason)}",
          :error
        )
    end

    {:noreply, hide_nav_delete_prompt(scene)}
  end

  def handle_event({:confirm_dialog_response, :nav_delete_prompt, :cancel}, _from, scene) do
    {:noreply, hide_nav_delete_prompt(scene)}
  end

  def handle_event({:confirm_dialog_response, :quit_prompt, :discard}, _from, scene) do
    new_scene = hide_quit_prompt(scene)
    Quillex.Lifecycle.Coordinator.discard_and_quit()
    {:noreply, new_scene}
  end

  def handle_event({:confirm_dialog_response, :quit_prompt, :cancel}, _from, scene) do
    new_scene = hide_quit_prompt(scene)
    Quillex.Lifecycle.Coordinator.cancel()
    {:noreply, new_scene}
  end

  def handle_event({:confirm_dialog_response, _id, :save}, _from, scene) do
    buf_ref = scene.assigns.state.pending_close_buf_ref
    new_scene = hide_unsaved_prompt(scene)
    {:noreply, saved_scene} = do_save(new_scene)
    handle_cast({:action, {:close_buffer, buf_ref}}, saved_scene)
  end

  def handle_event({:confirm_dialog_response, _id, :discard}, _from, scene) do
    buf_ref = scene.assigns.state.pending_close_buf_ref
    new_scene = hide_unsaved_prompt(scene)
    handle_cast({:action, {:close_buffer, buf_ref}}, new_scene)
  end

  def handle_event({:confirm_dialog_response, _id, :cancel}, _from, scene) do
    new_scene = hide_unsaved_prompt(scene)
    {:noreply, new_scene}
  end

  # --- Overlay ownership of the pointer ---
  # An IconMenu dropdown renders above the buffer pane, but the pane also
  # receives those clicks (it requests :cursor_button non-positionally).
  # Telling it explicitly beats making it guess from geometry — the old
  # guess also swallowed legitimate clicks on short and blank lines.
  # Uses the cheap flag-only message: this fires on every menu open/close
  # (including hover-switching between menus), and a full re-render per
  # transition is slow enough on a large document to stall the pane.
  # IconMenu also reports the dropdown's bounds, but in ITS coordinate space;
  # the pane compares against its own. Until that conversion exists, send the
  # boolean — a rect in the wrong space matches nothing, and the menu clicks
  # it should suppress end up moving the document cursor.
  def handle_event({:dropdown_opened, _menu_id, bounds}, _from, scene) when is_map(bounds) do
    Scenic.Scene.put_child(
      scene,
      :buffer_pane,
      {:set_overlay_open, dropdown_bounds_in_pane(scene.assigns.state, bounds)}
    )

    {:noreply, scene}
  end

  def handle_event({:dropdown_opened, _menu_id}, _from, scene) do
    Scenic.Scene.put_child(scene, :buffer_pane, {:set_overlay_open, true})
    {:noreply, scene}
  end

  def handle_event({:dropdown_closed}, _from, scene) do
    Scenic.Scene.put_child(scene, :buffer_pane, {:set_overlay_open, false})
    {:noreply, scene}
  end

  # IconMenu reports dropdown bounds in its own local coordinate space, while
  # TextField receives pointer coordinates in the pane's local space. Preserve
  # the precise rectangle instead of reducing it to `true`: the latter makes
  # the first click outside a persistent toggle menu look like a menu click and
  # silently drops it.
  defp dropdown_bounds_in_pane(state, bounds) do
    {root_x, root_y} = state.frame.pin.point
    icon_x = root_x + state.frame.size.width - scaled(@icon_menu_width, state)
    pane_x = root_x + if(side_pane_open?(state), do: state.file_nav_width, else: 0)

    # Find/Replace floats over the pane and does not move it.
    pane_y = root_y + scaled(@top_bar_height, state)

    %{
      x: icon_x + bounds.x - pane_x,
      y: root_y + bounds.y - pane_y,
      width: bounds.width,
      height: bounds.height
    }
  end

  defp scaled(value, state), do: max(1, round(value * state.chrome_zoom / 100))

  # Catch-all for unhandled events
  def handle_event(event, _from, scene) do
    Logger.debug("Unhandled event: #{inspect(event)}")
    {:noreply, scene}
  end

  # ===========================================================================
  # About dialog (Help → About)
  # ===========================================================================
  # The quote is the full text of the first commit in this repository
  # (2021-05-05) — the closest thing Quillex has to a design document.
  defp show_about_dialog(%{assigns: %{state: %{show_about: true}}} = scene) do
    {:noreply, scene}
  end

  defp show_about_dialog(scene) do
    state = scene.assigns.state
    vsn = Application.spec(:quillex, :vsn) |> to_string()

    graph =
      scene.assigns.graph
      |> ScenicWidgets.PopupModal.add_to_graph(
        %{
          frame: state.frame,
          title: "Quillex",
          body: [
            "v#{vsn} — a text editor written in Elixir, rendered by Scenic",
            "",
            "\"Simplicity is the highest goal, achievable when you have",
            "overcome all difficulties. After one has played a vast quantity",
            "of notes and more notes, it is simplicity that emerges as the",
            "crowning reward of art.\"",
            "— Frédéric Chopin (commit #1, 2021-05-05)",
            "",
            "github.com/JediLuke/quillex"
          ]
        },
        id: :about_dialog
      )

    new_scene =
      scene
      |> assign(state: %{state | show_about: true})
      |> assign(graph: graph)
      |> push_graph(graph)

    # Blur the editor so Enter/Escape talk to the modal, not the buffer.
    Scenic.Scene.put_child(new_scene, :buffer_pane, :blur)
    {:noreply, new_scene}
  end

  defp show_shortcuts_dialog(%{assigns: %{state: %{show_shortcuts: true}}} = scene),
    do: {:noreply, scene}

  defp show_shortcuts_dialog(scene) do
    state = scene.assigns.state

    graph =
      ScenicWidgets.PopupModal.add_to_graph(
        scene.assigns.graph,
        %{
          frame: state.frame,
          title: "Keyboard Shortcuts",
          body: Quillex.Commands.shortcut_lines(),
          # The reference lines up its two columns with padding, which only
          # lines up in a monospaced face.
          body_font: :ibm_plex_mono
        },
        id: :shortcuts_dialog
      )

    new_scene =
      scene
      |> assign(state: %{state | show_shortcuts: true})
      |> assign(graph: graph)
      |> push_graph(graph)

    Scenic.Scene.put_child(new_scene, :buffer_pane, :blur)
    {:noreply, new_scene}
  end

  # ===========================================================================
  # Private Helpers - Dirty State
  # ===========================================================================

  # Update the Ref dirty? flag in state when a buffer's dirty state changes.
  # This triggers tab bar re-render to show/hide the " *" indicator.
  defp maybe_update_dirty_state(scene, %Quillex.Buffer.Snapshot{ref: ref}),
    do: maybe_update_dirty_ref(scene, ref)

  defp maybe_update_dirty_state(scene, %Quillex.Structs.BufState{} = new_buf) do
    maybe_update_dirty_ref(scene, Quillex.Buffer.Ref.generate(new_buf))
  end

  defp maybe_update_dirty_ref(scene, %Quillex.Buffer.Ref{} = new_buf_ref) do
    state = scene.assigns.state

    # Find the matching Ref in the state's buffers list
    old_buf_ref = Enum.find(state.buffers, &(&1.uuid == new_buf_ref.uuid))

    if old_buf_ref && old_buf_ref.dirty? != new_buf_ref.dirty? do
      # Dirty state changed - update the Ref and re-render tab bar
      updated_buffers =
        Enum.map(state.buffers, fn b ->
          if b.uuid == new_buf_ref.uuid, do: new_buf_ref, else: b
        end)

      new_active =
        if state.active_buf && state.active_buf.uuid == new_buf_ref.uuid do
          new_buf_ref
        else
          state.active_buf
        end

      old_state = state
      new_state = %{state | buffers: updated_buffers, active_buf: new_active}

      new_graph =
        QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)
    else
      scene
    end
  end

  # ===========================================================================
  # Private Helpers - Status Notification
  # ===========================================================================

  # Display a transient notification message at the bottom of the viewport.
  # `severity` is :info | :warning | :error — controls background colour.
  # The message auto-clears after eight seconds via ViewStore's timer.
  #
  # Multiple rapid calls replace the previous message safely: each call stamps
  # the state with a fresh ref, and only the matching timer can clear it.
  # Stale timers (from earlier messages) see a different ref and are no-ops.
  # Status messages are ViewStore state: the store stamps, times out, and
  # clears them; the scene renders whatever the :radix_view snapshot carries.
  defp show_status(scene, message, severity) when is_binary(message) do
    Quillex.RadixCache.ViewStore.show_status(message, severity)
    {:noreply, scene}
  end

  # ===========================================================================
  # Private Helpers - Save
  # ===========================================================================

  defp do_save(scene) do
    case scene.assigns.state.active_buf do
      nil ->
        Logger.warning("No active buffer to save")
        {:noreply, scene}

      buf_ref ->
        case Quillex.Buffer.save(buf_ref) do
          {:ok, new_buf} -> {:noreply, maybe_update_dirty_state(scene, new_buf)}
          {:error, :no_path} -> show_file_picker_save(scene)
          {:error, reason} -> show_status(scene, "Save failed: #{inspect(reason)}", :error)
        end
    end
  end

  # ===========================================================================
  # Private Helpers - Editor Settings
  # ===========================================================================

  # Updates editor settings (word wrap, line numbers) and re-renders.
  # This syncs the TextField to the buffer first, then rebuilds with new settings.
  defp update_editor_settings(scene, new_state) do
    # With store_backed mode, just get cursor position from buffer (no sync needed)
    cursor_pos = get_buffer_cursor(scene)

    # Get first visible line for scroll preservation during word wrap toggle
    first_visible_line = get_first_visible_line(scene)

    # Update the IconMenu checkmarks to reflect new state
    new_menus = QuillEx.RootScene.Renderizer.build_menus(new_state)
    # put_child sends message to child but returns :ok, not scene
    Scenic.Scene.put_child(scene, :icon_menu, {:update_menus, new_menus})

    # Add cursor position and first visible line for restoration after re-render
    new_state = %{
      new_state
      | _restore_cursor: cursor_pos,
        _restore_first_visible_line: first_visible_line
    }

    # Reuse existing graph to preserve component PIDs and avoid race conditions
    old_state = scene.assigns.state

    new_graph =
      QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

    # Remove the temporary restore keys from state
    final_state = %{new_state | _restore_cursor: nil, _restore_first_visible_line: nil}

    new_scene =
      scene
      |> assign(state: final_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  # ===========================================================================
  # Private Helpers - Find/Search
  # ===========================================================================

  # Shows the search bar and optionally pre-fills with word under cursor.
  # Options:
  # - replace_mode: true to show replace row (Ctrl+H)
  #
  # This is the BUFFER's find, and only that. The project pane is a separate
  # surface with its own fields (see open_project_search/2): two boxes, two
  # jobs, no interaction between them.
  # The overlay rectangle has to follow the bar's HEIGHT. It is what tells the
  # editor pane which clicks belong to the bar, and the bar grows a second row
  # when the replacement field appears — with a stale one-row rectangle, every
  # click on the replacement field looked to the pane like a click in the
  # document, so the pane took the keyboard and the field went dead.
  defp refresh_search_overlay_rect(scene, state) do
    Scenic.Scene.put_child(
      scene,
      :buffer_pane,
      {:set_overlay_open, QuillEx.RootScene.Renderizer.search_bar_overlay_rect(state)}
    )

    :ok
  end

  # Shrink find-and-replace back to plain find, keeping the bar and the query.
  defp hide_replace_row(scene) do
    old_state = scene.assigns.state
    new_state = %{old_state | show_replace: false}

    new_graph =
      QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    Scenic.Scene.put_child(new_scene, :search_bar, :disable_replace_mode)
    refresh_search_overlay_rect(new_scene, new_state)
    {:noreply, new_scene}
  end

  defp show_search_bar(scene, opts \\ []) do
    replace_mode = Keyword.get(opts, :replace_mode, false)
    old_state = scene.assigns.state

    initial_query =
      if old_state.show_search_bar and old_state.search_query != "",
        do: old_state.search_query,
        else: word_under_cursor(old_state)

    cond do
      # Already showing: grow into replace mode (and keep everything else)
      old_state.show_search_bar and replace_mode ->
        new_state = %{old_state | show_replace: true}

        new_graph =
          QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

        new_scene =
          scene
          |> assign(state: new_state)
          |> assign(graph: new_graph)
          |> push_graph(new_graph)

        Scenic.Scene.put_child(new_scene, :search_bar, :enable_replace_mode)
        refresh_search_overlay_rect(new_scene, new_state)
        {:noreply, new_scene}

      true ->
        do_show_search_bar(scene, old_state, initial_query, replace_mode)
    end
  end

  # The word under the cursor — read from the BUFFER (the source of truth),
  # not by calling synchronously into the live TextField. That call blocks on
  # whatever the component is rendering; on a large document it timed out
  # and crashed the scene.
  defp word_under_cursor(state) do
    alias ScenicWidgets.TextField.State, as: TFState

    with buf_ref when not is_nil(buf_ref) <- state.active_buf,
         {:ok, buf_state} <- Quillex.Buffer.Process.fetch_buf(buf_ref),
         %{line: line, col: col} <- buf_state.cursor do
      TFState.word_at(buf_state.data, {line, col}) || ""
    else
      _ -> ""
    end
  end

  # ── The project-search pane ───────────────────────────────────────────────

  # Ctrl+Shift+F, Ctrl+Shift+H, and Search → Find in Project all land here.
  # Opening seeds the query field once — from what the pane last searched for,
  # or the word under the cursor — and hands the pane the keyboard. From then
  # on the field is the pane's.
  defp open_project_search(scene, opts) do
    old_state = scene.assigns.state
    focus = Keyword.get(opts, :focus, :query)
    remembered = Quillex.RadixCache.ProjectSearchStore.get_state().query

    seed =
      cond do
        remembered != "" -> remembered
        true -> word_under_cursor(old_state)
      end

    root = old_state.file_nav_path || File.cwd!()
    Quillex.RadixCache.ProjectSearchStore.set_root(root)
    Quillex.RadixCache.ProjectSearchStore.set_query(seed)
    Quillex.RadixCache.ViewStore.open_project_search()

    new_state = %{
      old_state
      | show_project_search: true,
        project_search_query: seed,
        project_search_focus_field: focus,
        keyboard_owner: :side_pane
    }

    new_graph =
      QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    # The pane owns the keyboard while it is up, so the editor must let go of
    # it — otherwise every character typed into the query field is also typed
    # into the document.
    Scenic.Scene.put_child(new_scene, :buffer_pane, :blur)
    Scenic.Scene.put_child(new_scene, :project_search_pane, {:set_query, seed})
    Scenic.Scene.put_child(new_scene, :project_search_pane, {:focus_field, focus})
    Scenic.Scene.put_child(new_scene, :project_search_pane, :focus)

    {:noreply, new_scene}
  end

  # Visit a search result. It opens into the PREVIEW tab — one reusable slot,
  # so walking thirty results leaves one tab open rather than thirty. The
  # outgoing preview is closed unless it has unsaved work or the user promoted
  # it; the incoming buffer takes the slot.
  defp open_preview_at(scene, path, {line, col}) do
    old_state = scene.assigns.state

    case Quillex.API.FileAPI.open(path) do
      {:ok, %{buffer_ref: buf_ref}} ->
        # Land on the match AND mark it. Arriving at a line with nothing
        # highlighted leaves you to find, by eye, the thing you just clicked
        # on — so the buffer is given the same query the pane ran, which
        # marks every occurrence in this file, and then the cursor is put on
        # the one that was clicked.
        #
        # In that order: setting the search jumps to the FIRST match, so a
        # cursor set before it would be immediately overridden.
        search = Quillex.RadixCache.ProjectSearchStore.get_state()

        {:ok, _snapshot} =
          Quillex.Buffer.dispatch(buf_ref, [
            {:search, search.query,
             [case_sensitive: search.case_sensitive, regex: search.regex]},
            {:set_cursor, {line, col}}
          ])

        close_stale_preview(old_state, buf_ref)

        # Keyboard stays with the pane: browsing results is the point, and the
        # next result is one more click away. Clicking in the editor takes it
        # back, through the ordinary focus routing in handle_regular_left_press.
        {:noreply, assign(scene, state: %{old_state | preview_buf_uuid: buf_ref.uuid})}

      {:error, reason} ->
        Quillex.RadixCache.ViewStore.show_status(to_string(reason), :warning)
        {:noreply, scene}
    end
  end

  # The previous preview goes away when the next result takes the slot — but
  # never if it has unsaved edits. Losing typed work to a click on a search
  # result would be indefensible; an extra tab is merely untidy.
  defp close_stale_preview(%{preview_buf_uuid: nil}, _incoming), do: :ok

  defp close_stale_preview(%{preview_buf_uuid: uuid}, %{uuid: uuid}), do: :ok

  defp close_stale_preview(%{preview_buf_uuid: uuid} = state, _incoming) do
    case Enum.find(state.buffers, &(&1.uuid == uuid)) do
      %{dirty?: false} = stale -> Quillex.Buffer.close(stale)
      _other -> :ok
    end
  end

  # A preview tab stops being provisional the moment it is edited — typing in a
  # file is the clearest possible statement that you meant to open it. It also
  # stops existing when the buffer does.
  defp surviving_preview(nil, _buffers), do: nil

  defp surviving_preview(uuid, buffers) do
    case Enum.find(buffers, &(&1.uuid == uuid)) do
      %{dirty?: false} -> uuid
      _promoted_or_gone -> nil
    end
  end

  # Promotion: the tab stops being provisional and becomes an ordinary one.
  # Both gestures that mean "I am staying here" — double-clicking the tab, and
  # editing the file — come through here.
  defp promote_preview(scene, uuid) do
    state = scene.assigns.state

    if state.preview_buf_uuid == uuid do
      new_state = %{state | preview_buf_uuid: nil}
      render_snapshot(scene, new_state)
    else
      scene
    end
  end

  defp side_pane_open?(state), do: state.show_file_nav or state.show_project_search

  defp side_pane_id(%{show_project_search: true}), do: :project_search_pane
  defp side_pane_id(_state), do: :file_nav

  # Hand the keyboard to exactly one pane.
  #
  # Both halves matter and both used to be done by hand at each call site: the
  # winner is told to focus, the loser is told to blur, AND the state records
  # who won — because the renderizer rebuilds the buffer pane from that state,
  # and a rebuild that disagrees hands the keyboard back to a pane that was
  # supposed to have let go of it.
  defp grant_keyboard(scene, owner) when owner in [:buffer, :side_pane] do
    state = scene.assigns.state
    side_pane = side_pane_id(state)

    case owner do
      :buffer ->
        if side_pane_open?(state), do: Scenic.Scene.put_child(scene, side_pane, :blur)

        # The find bar STAYS on screen when the document is clicked — it is
        # not thrown away by a click — but it must let go of the keyboard, and
        # the overlay gate has to come off with it. That gate is a second,
        # independent lock on the editor's key handling; leaving it on means
        # the click hands focus back to a pane that goes on ignoring every
        # keystroke.
        if state.show_search_bar do
          Scenic.Scene.put_child(scene, :search_bar, :blur)
          Scenic.Scene.put_child(scene, :buffer_pane, {:set_overlay_open, false})
        end

        Scenic.Scene.put_child(scene, :buffer_pane, :focus)

      :side_pane ->
        Scenic.Scene.put_child(scene, :buffer_pane, :blur)
        Scenic.Scene.put_child(scene, side_pane, :focus)
    end

    assign(scene, state: %{state | keyboard_owner: owner})
  end

  defp do_show_search_bar(scene, old_state, initial_query, replace_mode) do
    new_state = %{
      old_state
      | show_search_bar: true,
        search_query: initial_query,
        show_replace: replace_mode
    }

    # Blur the buffer pane BEFORE re-rendering. Showing the search bar
    # changes the layout, which recreates the pane — and the OUTGOING
    # instance stays alive, and focused, for a short window afterwards.
    # Blurring after the render leaves that dying instance eligible for
    # keystrokes, so the first characters of a search query get inserted
    # into the document (observed corrupting line 1 of an open file).
    Scenic.Scene.put_child(scene, :buffer_pane, :blur)

    # Belt and braces: mark that an overlay owns the keyboard. Focus is
    # granted/revoked by async messages, so blur alone leaves a window; the
    # overlay flag gates key input independently of the focus flag.
    #
    # The bar's RECTANGLE, not a blanket `true`. Told `true`, the pane drops
    # every click as "meant for the overlay" — and since the bar no longer
    # closes when the document is clicked, that left no way to get the
    # keyboard back at all.
    Scenic.Scene.put_child(
      scene,
      :buffer_pane,
      {:set_overlay_open, QuillEx.RootScene.Renderizer.search_bar_overlay_rect(new_state)}
    )

    # Reuse existing graph to preserve component PIDs and avoid race conditions
    new_graph =
      QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    # Belt-and-braces: the freshly created pane is built unfocused, but say
    # so explicitly in case it was created before this state landed.
    Scenic.Scene.put_child(new_scene, :buffer_pane, :blur)

    # If we have an initial query, perform search
    if String.length(initial_query) > 0 do
      Scenic.Scene.put_child(new_scene, :search_bar, {:set_query, initial_query})
      Scenic.Scene.put_child(new_scene, :buffer_pane, {:action, {:search, initial_query}})
    end

    {:noreply, new_scene}
  end

  # Hides the search bar and clears search state.
  defp hide_search_bar(scene) do
    new_state = %{
      scene.assigns.state
      | show_search_bar: false,
        show_replace: false,
        search_query: "",
        search_current_match: 0,
        search_total_matches: 0
    }

    # Clear search in TextField
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, :clear_search})

    # Reuse existing graph to preserve component PIDs and avoid race conditions
    old_state = scene.assigns.state

    new_graph =
      QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    # The overlay is gone: release the keyboard gate, then refocus.
    Scenic.Scene.put_child(new_scene, :buffer_pane, {:set_overlay_open, false})
    Scenic.Scene.put_child(new_scene, :buffer_pane, :focus)

    {:noreply, new_scene}
  end

  # Performs search and updates state.
  defp perform_search(scene, query, state) do
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, {:search, query, state.search_opts}})

    new_scene = scene |> assign(state: state)
    {:noreply, new_scene}
  end

  # ===========================================================================
  # Private Helpers - File Picker
  # ===========================================================================

  # Shows the file picker modal (for opening files).
  defp show_file_picker(scene) do
    new_state = %{scene.assigns.state | show_file_picker: true}

    # Add the file picker component to the graph
    graph =
      scene.assigns.graph
      |> ScenicWidgets.FilePicker.add_to_graph(
        %{
          frame: new_state.frame,
          start_path: System.user_home!(),
          mode: :open
        },
        id: :file_picker
      )

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: graph)
      |> push_graph(graph)

    # Blur the buffer pane so keystrokes go to FilePicker, not TextField
    Scenic.Scene.put_child(new_scene, :buffer_pane, :blur)

    {:noreply, new_scene}
  end

  # Shows the file picker modal in save mode (for saving files).
  defp show_file_picker_save(scene) do
    new_state = %{scene.assigns.state | show_file_picker: true}

    # Get the current buffer name as default filename
    default_filename =
      case scene.assigns.state.active_buf do
        nil ->
          "untitled.txt"

        buf_ref ->
          case Quillex.Buffer.Process.fetch_buf(buf_ref) do
            {:ok, buf} ->
              case buf.source do
                %{filepath: file_path} when is_binary(file_path) ->
                  # If buffer has a file path, use its basename
                  Path.basename(file_path)

                _ ->
                  # Otherwise use buffer name or default
                  buf.name || "untitled.txt"
              end

            _ ->
              "untitled.txt"
          end
      end

    # Add the file picker component in save mode
    graph =
      scene.assigns.graph
      |> ScenicWidgets.FilePicker.add_to_graph(
        %{
          frame: new_state.frame,
          start_path: System.user_home!(),
          mode: :save,
          filename: default_filename,
          font: Quillex.GUI.Theme.editor_font(14)
        },
        id: :file_picker
      )

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: graph)
      |> push_graph(graph)

    # IMPORTANT: Blur the buffer pane so keystrokes go to FilePicker, not TextField
    Scenic.Scene.put_child(new_scene, :buffer_pane, :blur)

    {:noreply, new_scene}
  end

  # Hides the file picker modal and optionally opens a file.
  defp hide_file_picker(scene, file_path \\ nil) do
    new_state = %{scene.assigns.state | show_file_picker: false}

    # Remove the file picker from the graph
    graph =
      scene.assigns.graph
      |> Scenic.Graph.delete(:file_picker)

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: graph)
      |> push_graph(graph)

    # Refocus the buffer pane
    Scenic.Scene.put_child(new_scene, :buffer_pane, :focus)

    # If a file was selected, open it
    if file_path do
      open_file(new_scene, file_path)
    else
      {:noreply, new_scene}
    end
  end

  # Hides the file picker modal and saves the current buffer to the specified path.
  defp hide_file_picker_and_save(scene, file_path) do
    new_state = %{scene.assigns.state | show_file_picker: false}

    # Remove the file picker from the graph
    graph =
      scene.assigns.graph
      |> Scenic.Graph.delete(:file_picker)

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: graph)
      |> push_graph(graph)

    # Save the current buffer to the specified path
    save_buffer_as(new_scene, file_path)
  end

  # ===========================================================================
  # Private Helpers - Unsaved Changes Prompt
  # ===========================================================================

  # Try to close a specific buffer. If it has unsaved changes, show the
  # Save/Discard/Cancel dialog and wait for a response before acting.
  # Clean buffers are closed immediately (no dialog shown).
  #
  # The close decision needs the authoritative dirty? flag. The :radix_buffers
  # snapshot keeps scene Refs fresh via edge-casts, but those hop through
  # two mailboxes (Buffer.Process → BufferManager → publish) — a synchronous
  # fresh-read from Buffer.Process is the race-free authority for a decision
  # as consequential as discarding a buffer.
  defp try_close_buffer(scene, %Quillex.Buffer.Ref{} = buf_ref) do
    fresh_buf_ref = refresh_buf_ref(buf_ref)

    case decide_close(scene.assigns.state, fresh_buf_ref) do
      :noop ->
        {:noreply, scene}

      {:close, br} ->
        handle_cast({:action, {:close_buffer, br}}, scene)

      {:show_prompt, br, _new_state} ->
        show_unsaved_prompt(scene, br)
    end
  end

  # Try to close the currently active buffer.
  # Returns {:noreply, scene} if there is no active buffer.
  defp try_close_active_buffer(scene) do
    case scene.assigns.state.active_buf do
      nil -> {:noreply, scene}
      buf_ref -> try_close_buffer(scene, buf_ref)
    end
  end

  # Fresh-read the Ref from Buffer.Process. The authoritative dirty? flag
  # lives in the buffer's own GenServer state — the copy in scene.assigns is a
  # cached snapshot from the last time RootScene actively applied an action.
  defp refresh_buf_ref(%Quillex.Buffer.Ref{} = buf_ref) do
    {:ok, buf_state} = Quillex.Buffer.Process.fetch_buf(buf_ref)
    Quillex.Buffer.Ref.generate(buf_state)
  end

  @doc false
  # Pure decision function for the close-buffer workflow. Public so unit tests
  # can exercise it without a live Scenic.Scene.
  #
  #   nil            → :noop (nothing to close)
  #   dirty? = true  → {:show_prompt, buf_ref, new_state} (state marks the prompt open)
  #   dirty? = false → {:close, buf_ref}
  def decide_close(%QuillEx.RootScene.State{} = state, active_buf) do
    case active_buf do
      nil ->
        :noop

      %Quillex.Buffer.Ref{dirty?: true} = buf_ref ->
        new_state = %{state | show_unsaved_prompt: true, pending_close_buf_ref: buf_ref}
        {:show_prompt, buf_ref, new_state}

      %Quillex.Buffer.Ref{} = buf_ref ->
        {:close, buf_ref}
    end
  end

  # Show the "Unsaved Changes" confirmation dialog.
  # Stores the pending buf_ref in state so the dialog response handlers can
  # retrieve it. Blurs the buffer pane so keystrokes (s/d/Escape) reach the
  # dialog component rather than the editor.
  defp show_unsaved_prompt(scene, buf_ref) do
    state = scene.assigns.state
    buf_name = buf_ref.name || "untitled"
    new_state = %{state | show_unsaved_prompt: true, pending_close_buf_ref: buf_ref}

    graph =
      scene.assigns.graph
      |> ScenicWidgets.ConfirmDialog.add_to_graph(
        %{
          frame: new_state.frame,
          title: "Unsaved Changes",
          message: "Save changes to \"#{buf_name}\" before closing?",
          buttons: [{:save, "Save"}, {:discard, "Discard"}, {:cancel, "Cancel"}]
        },
        id: :unsaved_prompt
      )

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: graph)
      |> push_graph(graph)

    # Blur the buffer pane so keystrokes go to the dialog, not the editor.
    Scenic.Scene.put_child(new_scene, :buffer_pane, :blur)

    {:noreply, new_scene}
  end

  # Hide the "Unsaved Changes" dialog and restore focus to the buffer pane.
  # Returns the new scene directly (not {:noreply, scene}) so callers can
  # continue processing — e.g. save the buffer and then close it in sequence.
  defp hide_unsaved_prompt(scene) do
    new_state = %{scene.assigns.state | show_unsaved_prompt: false, pending_close_buf_ref: nil}

    graph =
      scene.assigns.graph
      |> Scenic.Graph.delete(:unsaved_prompt)

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: graph)
      |> push_graph(graph)

    # Refocus the buffer pane.
    Scenic.Scene.put_child(new_scene, :buffer_pane, :focus)

    new_scene
  end

  def handle_info({:quit_requested, dirty_buffers}, scene) do
    names = Enum.map_join(dirty_buffers, "\n", &"• #{&1.name || "untitled"}")
    state = %{scene.assigns.state | show_unsaved_prompt: true, quit_dirty_buffers: dirty_buffers}

    graph =
      ScenicWidgets.ConfirmDialog.add_to_graph(
        scene.assigns.graph,
        %{
          frame: state.frame,
          title: "Unsaved Changes",
          message: "The following buffers have unsaved changes:\n\n#{names}",
          buttons: [{:discard, "Quit Without Saving"}, {:cancel, "Cancel"}]
        },
        id: :quit_prompt
      )

    new_scene = scene |> assign(state: state) |> assign(graph: graph) |> push_graph(graph)
    Scenic.Scene.put_child(new_scene, :buffer_pane, :blur)
    {:noreply, new_scene}
  end

  defp hide_quit_prompt(scene) do
    state = %{scene.assigns.state | show_unsaved_prompt: false, quit_dirty_buffers: []}
    graph = Scenic.Graph.delete(scene.assigns.graph, :quit_prompt)
    new_scene = scene |> assign(state: state) |> assign(graph: graph) |> push_graph(graph)
    Scenic.Scene.put_child(new_scene, :buffer_pane, :focus)
    new_scene
  end

  # Saves the current buffer to a new file path.
  defp save_buffer_as(scene, file_path) do
    case scene.assigns.state.active_buf do
      nil ->
        Logger.warning("No active buffer to save")
        {:noreply, scene}

      buf_ref ->
        Logger.info("Saving buffer as: #{file_path}")

        # Use the buffer's save_as action
        result = Quillex.Buffer.save_as(buf_ref, file_path)
        Logger.info("save_as result: #{inspect(result)}")

        case result do
          {:ok, updated_buf} ->
            Logger.info("Successfully saved to: #{file_path}, new name: #{updated_buf.name}")

            new_buf_ref = updated_buf.ref

            # Update the buffers list with the new Ref
            old_state = scene.assigns.state

            updated_buffers =
              Enum.map(old_state.buffers, fn b ->
                if b.uuid == buf_ref.uuid, do: new_buf_ref, else: b
              end)

            # Update state with new buffers list and active_buf
            new_state = %{old_state | buffers: updated_buffers, active_buf: new_buf_ref}

            # Re-render to update the tab bar with new filename
            new_graph =
              QuillEx.RootScene.Renderizer.render(
                scene.assigns.graph,
                scene,
                old_state,
                new_state
              )

            new_scene =
              scene
              |> assign(state: new_state)
              |> assign(graph: new_graph)
              |> push_graph(new_graph)

            # Refocus the buffer pane
            Scenic.Scene.put_child(new_scene, :buffer_pane, :focus)

            {:noreply, new_scene}

          {:error, reason} ->
            Logger.warning("Failed to save file: #{inspect(reason)}")
            {:noreply, scene}

          other ->
            Logger.warning("Unexpected save_as result: #{inspect(other)}")
            {:noreply, scene}
        end
    end
  end

  # Opens a file and creates a new buffer for it.
  defp open_file(scene, file_path) do
    Logger.info("Opening file: #{file_path}")

    case Quillex.API.FileAPI.open(file_path) do
      {:ok, %{buffer_ref: _buf_ref, lines: lines, bytes: bytes}} ->
        Logger.info("Opened file with #{lines} lines, #{bytes} bytes")

        # The FileAPI.open already switches to the new buffer and broadcasts
        # the :new_buffer_opened message, so we just need to wait for that
        {:noreply, scene}

      {:error, reason} ->
        Logger.warning("Failed to open file: #{reason}")
        Quillex.RadixCache.ViewStore.show_status(to_string(reason), :warning)
        {:noreply, scene}
    end
  end

  defp hide_nav_delete_prompt(scene) do
    state = %{scene.assigns.state | pending_nav_delete: [], show_nav_delete_prompt: false}
    graph = Scenic.Graph.delete(scene.assigns.graph, :nav_delete_prompt)
    new_scene = scene |> assign(state: state, graph: graph) |> push_graph(graph)
    Scenic.Scene.put_child(new_scene, :buffer_pane, :focus)
    new_scene
  end

  defp entry_word(1), do: "entry"
  defp entry_word(_count), do: "entries"

  defp format_nav_error({:destination_exists, path}),
    do: "#{Path.basename(path)} already exists"

  defp format_nav_error({:missing_source, path}), do: "#{Path.basename(path)} no longer exists"
  defp format_nav_error({:invalid_target, path}), do: "#{path} is not a directory"
  defp format_nav_error(:move_into_self), do: "a directory cannot be moved into itself"
  defp format_nav_error(:already_in_target), do: "the selection is already in that directory"

  defp format_nav_error({:move_into_descendant, _source, _target}),
    do: "a directory cannot be moved into its descendant"

  defp format_nav_error(reason), do: inspect(reason)
end
