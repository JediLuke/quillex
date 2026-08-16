defmodule QuillEx.RootScene do
  use Scenic.Scene
  alias QuillEx.RootScene
  require Logger

  # Layout constants — must stay in sync with qlx_root_scene_renderizer.ex
  @top_bar_height 35
  @search_bar_height 36

  # Line height of the buffer pane text (must match BufferPane font_size).
  # Used to estimate the visible page size for Page Up / Page Down navigation.
  @line_height 24

  # Icon menu constants — must match ScenicWidgets.IconMenu default theme values
  # and the icon_menu_width used in qlx_root_scene_renderizer.ex
  @icon_menu_width 140
  @dropdown_width 180

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
      |> assign(graph: graph)
      |> push_graph(graph)

    Process.register(self(), __MODULE__)

    # Subscribe to the stores AFTER the first push: the retained snapshots
    # arrive as normal updates instead of racing init
    Scenic.PubSub.subscribe(Quillex.RadixCache.Sources.buffers())
    Scenic.PubSub.subscribe(Quillex.RadixCache.Sources.view())

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
    current_frame = scene.assigns.state.frame
    current_size = {current_frame.size.width, current_frame.size.height}

    # Only re-render if size actually changed (avoids double-render on bootup)
    if current_size != new_vp_size do
      Logger.debug("#{__MODULE__} reshape: #{inspect(current_size)} -> #{inspect(new_vp_size)}")

      # With store_backed mode, Buffer.Process is the source of truth.
      # TextField sends all changes directly to Buffer, so we don't need to sync.
      # Just get the current cursor position from the buffer for restoration.
      cursor_pos = get_buffer_cursor(scene)

      # The pane IS recreated on reshape, so save the scroll position to
      # restore into the new instance.
      first_visible_line = get_first_visible_line(scene)

      # Create new frame with the resized dimensions
      new_frame = Widgex.Frame.new(pin: {0, 0}, size: new_vp_size)

      # Update state with new frame and saved cursor position for the renderizer
      old_state = scene.assigns.state

      new_state =
        old_state
        |> Map.put(:frame, new_frame)
        |> Map.put(:_restore_cursor, cursor_pos)
        |> Map.put(:_restore_first_visible_line, first_visible_line)

      # Reuse existing graph to preserve component PIDs and avoid race conditions
      new_graph =
        QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

      # Remove the temporary restore keys from state
      final_state =
        new_state
        |> Map.delete(:_restore_cursor)
        |> Map.delete(:_restore_first_visible_line)

      new_scene =
        scene
        |> assign(state: final_state)
        |> assign(graph: new_graph)
        |> push_graph(new_graph)

      {:noreply, new_scene}
    else
      # Size unchanged, don't re-render (handles the double-call on bootup)
      {:noreply, scene}
    end
  end

  # Track cursor position for scroll routing
  def handle_input({:cursor_pos, coords}, _context, scene) do
    state = scene.assigns.state
    new_state = %{state | cursor_pos: coords}
    {:noreply, assign(scene, state: new_state)}
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
    if state.show_file_nav and click_y > @top_bar_height and
         not state.show_unsaved_prompt and not state.show_about and not state.show_shortcuts do
      if click_x < state.file_nav_width do
        Scenic.Scene.put_child(scene, :file_nav, :focus)
        Scenic.Scene.put_child(scene, :buffer_pane, :blur)
      else
        Scenic.Scene.put_child(scene, :file_nav, :blur)
        Scenic.Scene.put_child(scene, :buffer_pane, :focus)
      end
    end

    # --- Search bar ---
    # Close the search bar when the click lands below it (in the buffer area).
    search_height = if state.show_replace, do: @search_bar_height * 2, else: @search_bar_height

    if state.show_search_bar and click_y > @top_bar_height + search_height do
      hide_search_bar(scene)
    else
      {:noreply, scene}
    end
  end

  # Mouse clicks on child components (TextField, IconMenu, FilePicker, etc.) are
  # handled by those components via Scenic's hit-testing and their own
  # request_input registrations.  This catch-all handles any remaining events.
  def handle_input(_input, _context, scene) do
    {:noreply, scene}
  end

  # Dispatch a single buffer action to the currently active buffer.
  # Calls the Buffer.Process synchronously, then pushes the resulting state
  # to the BufferPane (TextField) for an immediate UI update.  Also updates
  # the dirty indicator in the tab bar.  When no buffer is active (e.g. during
  # startup) the call is silently ignored and the scene is returned unchanged.
  # Compute how many lines fit in the visible buffer area.
  # Uses the current viewport frame height, subtracts the top bar, and divides
  # by the buffer line height. Falls back to 20 if the frame is not yet set.
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
      state.show_search_bar or state.show_unsaved_prompt or
        Map.get(state, :show_about, false) or Map.get(state, :show_shortcuts, false) or
          state.show_file_picker ->
        {:noreply, scene}

      true ->
        do_dispatch_to_active_buffer(scene, action)
    end
  end

  defp keyboard_overlay_open?(state) do
    state.show_search_bar or state.show_unsaved_prompt or state.show_file_picker or
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

      new_state =
        Enum.reduce(actions, old_state, fn action, acc_state ->
          RootScene.Reducer.process(acc_state, action)
        end)

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
    # Update state with new query
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

  def handle_cast({:search_next, _id}, scene) do
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, :find_next})
    {:noreply, scene}
  end

  def handle_cast({:search_prev, _id}, scene) do
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, :find_prev})
    {:noreply, scene}
  end

  def handle_cast({:search_close, _id}, scene) do
    hide_search_bar(scene)
  end

  def handle_cast({:replace_requested, _id, replacement}, scene) do
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, {:replace, replacement}})
    {:noreply, scene}
  end

  def handle_cast({:replace_all_requested, _id, replacement}, scene) do
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, {:replace_all, replacement}})
    {:noreply, scene}
  end

  defp dispatch_toggle(:toggle_line_numbers),
    do: Quillex.RadixCache.ViewStore.toggle_line_numbers()

  defp dispatch_toggle(:toggle_word_wrap), do: Quillex.RadixCache.ViewStore.toggle_word_wrap()
  defp dispatch_toggle(:toggle_file_nav), do: Quillex.RadixCache.ViewStore.toggle_file_nav()

  # Buffer-list store snapshots (:radix_buffers) — the single path by which
  # the open-buffers list, active buffer, and dirty flags reach the scene.
  def handle_info(
        {{Scenic.PubSub, :data}, {:radix_buffers, %{buffers: buffers, active_buf: active}, _ts}},
        scene
      ) do
    new_state = %{scene.assigns.state | buffers: buffers, active_buf: active}
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

    if editor_layout_changed?(old_state, new_state) do
      update_editor_settings(scene, new_state)
    else
      {:noreply, render_snapshot(scene, new_state)}
    end
  end

  # Scenic.PubSub lifecycle notifications — deliberately specific clauses, a
  # catch-all on {{Scenic.PubSub, _}, _} would swallow :data updates.
  def handle_info({{Scenic.PubSub, :registered}, _}, scene), do: {:noreply, scene}
  def handle_info({{Scenic.PubSub, :unregistered}, _}, scene), do: {:noreply, scene}

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
    :word_wrap,
    :tab_width,
    :text_size,
    :show_file_nav,
    :file_nav_path,
    :file_nav_width,
    :status_message,
    :status_severity
  ]

  defp merge_view(state, view), do: struct(state, Map.take(view, @view_keys))

  defp editor_layout_changed?(old_state, new_state) do
    Enum.any?(
      [:show_line_numbers, :word_wrap, :tab_width, :text_size, :show_file_nav],
      fn key -> Map.get(old_state, key) != Map.get(new_state, key) end
    )
  end

  # Handle events from child components (IconMenu, TabBar, etc.)
  def handle_event({:menu_value_changed, "text_size", value}, _from, scene) do
    Quillex.RadixCache.ViewStore.set_text_size(round(value))
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

      "file_nav" ->
        Quillex.RadixCache.ViewStore.toggle_file_nav()
        {:noreply, scene}

      "line_numbers" ->
        Quillex.RadixCache.ViewStore.toggle_line_numbers()
        {:noreply, scene}

      "word_wrap" ->
        Quillex.RadixCache.ViewStore.toggle_word_wrap()
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

      "tab_width_" <> n when n in ["2", "3", "4", "8"] ->
        Quillex.RadixCache.ViewStore.set_tab_width(String.to_integer(n))
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

  # Handle file navigation from SideNav (file explorer sidebar)
  def handle_event({:sidebar, :navigate, item_id}, _from, scene) when is_binary(item_id) do
    # item_id is the file path
    if File.regular?(item_id) do
      Logger.info("File nav: opening file #{item_id}")
      # Opening a file moves the user's attention to the editor: hand keyboard
      # focus back so they can type immediately (and the nav stops eating keys).
      Scenic.Scene.put_child(scene, :file_nav, :blur)
      Scenic.Scene.put_child(scene, :buffer_pane, :focus)
      open_file(scene, item_id)
    else
      Logger.debug("File nav: not a regular file: #{item_id}")
      {:noreply, scene}
    end
  end

  # Handle expand/collapse events from SideNav (informational only)
  def handle_event({:sidebar, :expand, _item_id}, _from, scene), do: {:noreply, scene}
  def handle_event({:sidebar, :collapse, _item_id}, _from, scene), do: {:noreply, scene}
  def handle_event({:sidebar, :hover, _item_id}, _from, scene), do: {:noreply, scene}

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
  def handle_event({:dropdown_opened, _menu_id, _bounds}, _from, scene) do
    Scenic.Scene.put_child(scene, :buffer_pane, {:set_overlay_open, true})
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
          body: Quillex.Commands.shortcut_lines()
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
  # The message auto-clears after 5 seconds via a {:clear_status_message, ref} timer.
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
    new_state =
      if cursor_pos do
        Map.put(new_state, :_restore_cursor, cursor_pos)
      else
        new_state
      end

    new_state =
      if first_visible_line do
        Map.put(new_state, :_restore_first_visible_line, first_visible_line)
      else
        new_state
      end

    # Reuse existing graph to preserve component PIDs and avoid race conditions
    old_state = scene.assigns.state

    new_graph =
      QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

    # Remove the temporary restore keys from state
    final_state =
      new_state
      |> Map.delete(:_restore_cursor)
      |> Map.delete(:_restore_first_visible_line)

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
  defp show_search_bar(scene, opts \\ []) do
    alias ScenicWidgets.TextField.State, as: TFState
    replace_mode = Keyword.get(opts, :replace_mode, false)

    # Pre-fill the search with the word under the cursor — read from the
    # BUFFER (the source of truth), not by calling synchronously into the
    # live TextField. That call blocks on whatever the component is
    # rendering; on a large document it timed out and crashed the scene.
    initial_query =
      with buf_ref when not is_nil(buf_ref) <- scene.assigns.state.active_buf,
           {:ok, buf_state} <- Quillex.Buffer.Process.fetch_buf(buf_ref),
           %{line: line, col: col} <- buf_state.cursor do
        TFState.word_at(buf_state.data, {line, col}) || ""
      else
        _ -> ""
      end

    old_state = scene.assigns.state

    # If search bar is already showing and we're toggling replace mode, just update replace
    if old_state.show_search_bar and replace_mode do
      new_state = %{old_state | show_replace: true}

      new_graph =
        QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

      new_scene =
        scene
        |> assign(state: new_state)
        |> assign(graph: new_graph)
        |> push_graph(new_graph)

      Scenic.Scene.put_child(new_scene, :search_bar, :enable_replace_mode)
      {:noreply, new_scene}
    else
      do_show_search_bar(scene, old_state, initial_query, replace_mode)
    end
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
    Scenic.Scene.put_child(scene, :buffer_pane, {:set_overlay_open, true})

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
    # Send search action to TextField
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, {:search, query}})

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
        {:noreply, scene}
    end
  end
end
