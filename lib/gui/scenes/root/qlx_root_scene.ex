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

    state = QuillEx.RootScene.State.new(%{
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
    Quillex.Utils.PubSub.subscribe(topic: :qlx_events)

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
  # Supports undo via Ctrl+U.
  def handle_input({:key, {:key_d, 1, [:ctrl]}}, _context, scene) do
    dispatch_to_active_buffer(scene, :delete_line)
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
  # to the buffer controller in buffer_backed mode, which is the single
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

      # With buffer_backed mode, Buffer.Process is the source of truth.
      # TextField sends all changes directly to Buffer, so we don't need to sync.
      # Just get the current cursor position from the buffer for restoration.
      cursor_pos = get_buffer_cursor(scene)

      # Create new frame with the resized dimensions
      new_frame = Widgex.Frame.new(pin: {0, 0}, size: new_vp_size)

      # Update state with new frame and saved cursor position for the renderizer
      old_state = scene.assigns.state
      new_state = old_state
        |> Map.put(:frame, new_frame)
        |> Map.put(:_restore_cursor, cursor_pos)

      # Reuse existing graph to preserve component PIDs and avoid race conditions
      new_graph = QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

      # Remove the temporary cursor restore key from state
      final_state = Map.delete(new_state, :_restore_cursor)

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

  # Route scroll events to the appropriate component based on cursor position
  def handle_input({:cursor_scroll, scroll_data}, _context, scene) do
    state = scene.assigns.state
    {cursor_x, _cursor_y} = state.cursor_pos

    # Determine which component should receive the scroll based on cursor position
    # If file_nav is visible and cursor is within its width, route to file_nav
    if state.show_file_nav and cursor_x < state.file_nav_width do
      # Route scroll to file navigator
      Scenic.Scene.put_child(scene, :file_nav, %{scroll: scroll_data})
    end
    # Note: buffer_pane (TextField in buffer_backed mode) handles its own scroll
    # via request_input/cursor_scroll - no need to forward via put_child

    {:noreply, scene}
  end

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
    case scene.assigns.state.active_buf do
      nil ->
        {:noreply, scene}

      buf_ref ->
        {:ok, new_buf} = Quillex.Buffer.BufferManager.call_buffer(buf_ref, {:action, action})

        # Push updated buffer state to the TextField component immediately.
        {:ok, [pid]} = Scenic.Scene.child(scene, :buffer_pane)
        GenServer.cast(pid, {:state_change, new_buf})

        # Reflect any dirty change in the tab bar.
        scene = maybe_update_dirty_state(scene, new_buf)

        {:noreply, scene}
    end
  end

  # Get the cursor position from the active buffer (Buffer.Process is source of truth)
  defp get_buffer_cursor(scene) do
    with buf_ref when not is_nil(buf_ref) <- scene.assigns.state.active_buf,
         {:ok, buf_state} <- Quillex.Buffer.Process.fetch_buf(buf_ref),
         [%{line: line, col: col} | _] <- buf_state.cursors do
      {line, col}
    else
      _ -> nil
    end
  end

  # Get the first visible line from the TextField (for scroll preservation during word wrap toggle)
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

  # Synchronous action processing for BufferPane actions
  def handle_call({Quillex.GUI.Components.BufferPane, :action, buf_ref, actions}, _from, scene) do
    # Processing BufferPane actions synchronously (same logic as handle_cast)
    {:ok, new_buf} = Quillex.Buffer.BufferManager.call_buffer(buf_ref, {:action, actions})

    # Update the GUI with new buffer state synchronously
    {:ok, [pid]} = Scenic.Scene.child(scene, :buffer_pane)
    GenServer.call(pid, {:state_change, new_buf})

    # Update dirty state in BufRef so tab bar shows " *" indicator
    scene = maybe_update_dirty_state(scene, new_buf)

    {:reply, :ok, scene}
  end

  # Handle editor settings toggle actions specially - they need update_editor_settings flow
  def handle_call({:action, [:toggle_line_numbers]}, _from, scene) do
    state = scene.assigns.state
    new_state = %{state | show_line_numbers: not state.show_line_numbers}
    {:noreply, new_scene} = update_editor_settings(scene, new_state)
    {:reply, :ok, new_scene}
  end

  def handle_call({:action, [:toggle_word_wrap]}, _from, scene) do
    state = scene.assigns.state
    new_state = %{state | word_wrap: not state.word_wrap}
    {:noreply, new_scene} = update_editor_settings(scene, new_state)
    {:reply, :ok, new_scene}
  end

  def handle_call({:action, [:toggle_file_nav]}, _from, scene) do
    state = scene.assigns.state
    new_state = %{state | show_file_nav: not state.show_file_nav}
    {:noreply, new_scene} = update_editor_settings(scene, new_state)
    {:reply, :ok, new_scene}
  end

  # Open a file - handled outside the action pipeline to avoid timing issues
  # with PubSub-based buffer activation
  def handle_call({:action, [{:open_file, path}]}, _from, scene) when is_binary(path) do
    case File.read(path) do
      {:ok, content} ->
        {:ok, _buf_ref} = Quillex.Buffer.BufferManager.new_buffer(%{
          name: Path.basename(path),
          source: %{filepath: path},
          data: String.split(content, "\n"),
          dirty: false
        })
        {:reply, :ok, scene}

      {:error, reason} ->
        Logger.warning("Failed to open file: #{path}, reason: #{inspect(reason)}")
        {:reply, {:error, reason}, scene}
    end
  end

  def handle_call({:action, actions}, _from, scene) when is_list(actions) do
    # With buffer_backed mode, no need to sync - Buffer.Process is source of truth
    # Processing actions from RadixReducer (synchronous version)
    case process_actions(scene, actions) do
      {:ok, {new_state, new_graph}} ->
        new_scene =
          scene
          |> assign(state: new_state)
          |> assign(graph: new_graph)
          |> push_graph(new_graph)

        {:reply, :ok, new_scene}

      {:error, reason} ->
        Logger.warning("Couldn't compute action #{inspect(actions)}. #{inspect(reason)}")
        {:reply, {:error, reason}, scene}
    end
  end

  def handle_call({:action, a}, _from, scene) do
    # wrap singular actions in a list and push through the multi-action pipeline anyway
    handle_call({:action, [a]}, nil, scene)
  end

  defp process_actions(scene, actions) do
    # wormhole will wrap this function in an ok/error tuple even if it crashes
    Wormhole.capture(fn ->
      old_state = scene.assigns.state

      new_state =
        Enum.reduce(actions, old_state, fn action, acc_state ->
          RootScene.Reducer.process(acc_state, action)
          |> case do
            :ignore ->
              acc_state

            # :cast_to_children ->
            #   Scenic.Scene.cast_children(scene, action)
            #   acc_state

            new_acc_state ->
              new_acc_state
          end
        end)

      # Reuse existing graph to preserve component PIDs and avoid race conditions
      # during rapid buffer switches. Pass old_state to enable smart component updates
      # (only recreate when truly necessary, like switching buffers).
      new_graph = QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

      {new_state, new_graph}
    end)
  end

  # Handle editor settings toggle actions specially - they need update_editor_settings flow
  def handle_cast({:action, [:toggle_line_numbers]}, scene) do
    state = scene.assigns.state
    new_state = %{state | show_line_numbers: not state.show_line_numbers}
    update_editor_settings(scene, new_state)
  end

  def handle_cast({:action, [:toggle_word_wrap]}, scene) do
    state = scene.assigns.state
    new_state = %{state | word_wrap: not state.word_wrap}
    update_editor_settings(scene, new_state)
  end

  def handle_cast({:action, [:toggle_file_nav]}, scene) do
    state = scene.assigns.state
    new_state = %{state | show_file_nav: not state.show_file_nav}
    update_editor_settings(scene, new_state)
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
                Logger.warning("[run_verification] File has been modified on disk since last save")
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
            Logger.debug("[run_verification] Skipped (failed to fetch buffer state): #{inspect(reason)}")
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
                Logger.info("[reload_from_disk] Reloaded #{length(new_lines)} lines from #{file_path}")
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
            Logger.debug("[reload_from_disk] Skipped (failed to fetch buffer state): #{inspect(reason)}")
            {:noreply, scene}
        end
    end
  end

  def handle_cast({:action, actions}, scene) when is_list(actions) do
    # With buffer_backed mode, no need to sync - Buffer.Process is source of truth
    # Processing actions from RadixReducer
    case process_actions(scene, actions) do
      {:ok, {new_state, new_graph}} ->
        new_scene =
          scene
          |> assign(state: new_state)
          |> assign(graph: new_graph)
          |> push_graph(new_graph)

        {:noreply, new_scene}

      {:error, reason} ->
        # this is a big problem but we still dont want to crash the root scene over it (right ?)
        Logger.warning("Couldn't compute action #{inspect(actions)}. #{inspect(reason)}")

        #TODO recovery idea - there is a possibility that we sometimes have a race condition
        # and that's why this happens, e.g. we open a buffer via BufferManager, BfrMgr is supposed
        # to broadcast out changes like "buffer opened" when it's done, but what if between that
        # happening someone came in here with an action like "open buffer x" which, technically
        # has been opened, but the msg hasn't got back to the GUI process yet cause, race condition

        # there's 2 ideas to make this more robust
        # 1- we could have a repetition here, if it failed, send the action back to ourself 50ms
        # from now, and try again. Then we need to keep track of state so we dont indefinitely keep retrying forever
        # 2- we could also listen to the pubsub broadcast channel from the API, and make it
        # wait for acknowledgement that way
        {:noreply, scene}
    end
  end

  #TODO differentiate between :gui_action

  def handle_cast({:action, a}, scene) do
    # wrap singular actions in a list and push through the multi-action pipeline anyway
    handle_cast({:action, [a]}, scene)
  end

  # these actions bubble up from the BufferPane component, we simply forward them to the Buffer process
  # this is where we ought to simply fwd the actions, and await a callback - we're the GUI, we just react
  def handle_cast(
        {
          Quillex.GUI.Components.BufferPane,
          :action,
          %Quillex.Structs.BufState.BufRef{} = buf_ref,
          actions
        },
        scene
      ) do
    # Processing BufferPane actions
    Logger.debug("[ROOT_SCENE] Received BufferPane actions: #{inspect(actions)}")

    # Flamelex.Fluxus.action()

    # interact with the Buffer state to apply the actions - thisd is equivalent to Fluxus
    # Applying actions to buffer
    {:ok, new_buf} = Quillex.Buffer.BufferManager.call_buffer(buf_ref, {:action, actions})
    Logger.debug("[ROOT_SCENE] Buffer action processed, new cursors: #{inspect(new_buf.cursors)}")
    # Buffer state updated

    # # we normally would broadcast changesd from Fluxus, since RootScene _id_ fluxus here, here is where we broadcast from

    # # alternativaly...
    # # maybe root scene should listen to qlx_events, get that buffer updated, then in there, go fetch thye buffer & then push the updated down...
    # # that would be more like how flamelex does it
    # # and it allows us to proapagate changes up from quillex to flamelex in same mechanism

    # # update the GUI
    # Updating GUI with new buffer state
    {:ok, [pid]} = Scenic.Scene.child(scene, :buffer_pane)
    GenServer.cast(pid, {:state_change, new_buf})
    # GUI update complete

    # Update dirty state in BufRef so tab bar shows " *" indicator
    scene = maybe_update_dirty_state(scene, new_buf)

    {:noreply, scene}
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

  # Clear the transient status notification (fired by Process.send_after from show_status/3).
  #
  # The ref-based match ensures only the timer for the *current* message can clear
  # it.  If show_status/3 was called again before this timer fired, the state holds
  # a different ref, so this is a no-op — the newer message is preserved for its
  # full 5-second window.
  def handle_info({:clear_status_message, ref}, scene) do
    state = scene.assigns.state
    if state.status_ref == ref do
      new_state = %{state | status_message: nil, status_ref: nil}
      old_state = state
      new_graph = QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)
      new_scene =
        scene
        |> assign(state: new_state)
        |> assign(graph: new_graph)
        |> push_graph(new_graph)
      {:noreply, new_scene}
    else
      {:noreply, scene}
    end
  end

  # if actions come in via PubSub they come in via handle_info, just convert to handle_cast
  def handle_info({:action, a}, scene) do
    handle_cast({:action, a}, scene)
  end

  def handle_info({:new_buffer_opened, %Quillex.Structs.BufState.BufRef{} = buf_ref}, scene) do
    new_state =
      scene.assigns.state
      |> RootScene.Mutator.add_buffer(buf_ref)
      |> RootScene.Mutator.activate_buffer(buf_ref)

    # Reuse existing graph to preserve component PIDs and avoid race conditions
    old_state = scene.assigns.state
    new_graph = QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_info({:ubuntu_bar_button_clicked, button_id, _button}, scene) do
    # UbuntuBar button clicked: #{button_id}"

    # Handle different button actions
    case button_id do
      :new_file ->
        # Create a new buffer
        handle_cast({:action, :new_buffer}, scene)

      :open_file ->
        show_file_picker(scene)

      :save_file ->
        do_save(scene)

      :search ->
        show_search_bar(scene)

      :settings ->
        # Settings functionality not implemented yet
        {:noreply, scene}

      _other ->
        Logger.warning("Unknown ubuntu bar button: #{inspect(button_id)}")
        {:noreply, scene}
    end
  end

  # Handle events from child components (IconMenu, TabBar, etc.)
  def handle_event({:menu_item_clicked, item_id}, _from, scene) do
    Logger.debug("Menu item clicked: #{inspect(item_id)}")

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
        # Toggle file navigator sidebar
        state = scene.assigns.state
        new_state = %{state | show_file_nav: not state.show_file_nav}
        Logger.debug("Toggling file nav: #{new_state.show_file_nav}")
        update_editor_settings(scene, new_state)

      "line_numbers" ->
        # Toggle line numbers
        state = scene.assigns.state
        new_state = %{state | show_line_numbers: not state.show_line_numbers}
        Logger.debug("Toggling line numbers: #{new_state.show_line_numbers}")
        update_editor_settings(scene, new_state)

      "word_wrap" ->
        # Toggle word wrap
        state = scene.assigns.state
        new_state = %{state | word_wrap: not state.word_wrap}
        Logger.debug("Toggling word wrap: #{new_state.word_wrap}")
        update_editor_settings(scene, new_state)

      "tab_width_2" ->
        state = scene.assigns.state
        new_state = %{state | tab_width: 2}
        Logger.debug("Setting tab width: 2")
        update_editor_settings(scene, new_state)

      "tab_width_3" ->
        state = scene.assigns.state
        new_state = %{state | tab_width: 3}
        Logger.debug("Setting tab width: 3")
        update_editor_settings(scene, new_state)

      "tab_width_4" ->
        state = scene.assigns.state
        new_state = %{state | tab_width: 4}
        Logger.debug("Setting tab width: 4")
        update_editor_settings(scene, new_state)

      "tab_width_8" ->
        state = scene.assigns.state
        new_state = %{state | tab_width: 8}
        Logger.debug("Setting tab width: 8")
        update_editor_settings(scene, new_state)

      "about" ->
        # About dialog - not implemented yet
        Logger.info("Quillex - A simple text editor built with Scenic")
        {:noreply, scene}

      "shortcuts" ->
        # Keyboard shortcuts - not implemented yet
        {:noreply, scene}

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
      # With buffer_backed mode, Buffer.Process is source of truth - no sync needed
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
      # With buffer_backed mode, Buffer.Process is source of truth — show
      # unsaved-changes dialog if dirty, otherwise close immediately.
      try_close_buffer(scene, buf_ref)
    else
      Logger.warning("Could not find buffer for tab close: #{inspect(tab_id)}")
      {:noreply, scene}
    end
  end

  # Save file (Ctrl+S from TextField)
  def handle_event({:save_requested, _id, _text}, _from, scene) do
    # With buffer_backed mode, Buffer.Process already has current content - no sync needed
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

  # Search bar events - query changed
  def handle_event({:search_query_changed, _id, query}, _from, scene) do
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

  # Search bar events - next match
  def handle_event({:search_next, _id}, _from, scene) do
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, :find_next})
    {:noreply, scene}
  end

  # Search bar events - previous match
  def handle_event({:search_prev, _id}, _from, scene) do
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, :find_prev})
    {:noreply, scene}
  end

  # Search bar events - close
  def handle_event({:search_close, _id}, _from, scene) do
    hide_search_bar(scene)
  end

  # Replace events - replace current match
  def handle_event({:replace_requested, _id, replacement}, _from, scene) do
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, {:replace, replacement}})
    {:noreply, scene}
  end

  # Replace events - replace all matches
  def handle_event({:replace_all_requested, _id, replacement}, _from, scene) do
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, {:replace_all, replacement}})
    {:noreply, scene}
  end

  # Search complete (from TextField after parallel search)
  def handle_event({:search_complete, _id, query, match_count}, _from, scene) do
    Logger.debug("[search] #{match_count} matches for #{inspect(query)}")

    # Update state with match count
    new_state = %{scene.assigns.state |
      search_total_matches: match_count,
      search_current_match: if(match_count > 0, do: 1, else: 0)
    }

    # Update the search bar's match count display
    Scenic.Scene.put_child(scene, :search_bar, {:set_matches, new_state.search_current_match, match_count})

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

  # Catch-all for unhandled events
  def handle_event(event, _from, scene) do
    Logger.debug("Unhandled event: #{inspect(event)}")
    {:noreply, scene}
  end

  # ===========================================================================
  # Private Helpers - Dirty State
  # ===========================================================================

  # Update the BufRef dirty? flag in state when a buffer's dirty state changes.
  # This triggers tab bar re-render to show/hide the " *" indicator.
  defp maybe_update_dirty_state(scene, %Quillex.Structs.BufState{} = new_buf) do
    state = scene.assigns.state

    # Find the matching BufRef in the state's buffers list
    old_buf_ref = Enum.find(state.buffers, & &1.uuid == new_buf.uuid)

    if old_buf_ref && old_buf_ref.dirty? != new_buf.dirty? do
      # Dirty state changed - update the BufRef and re-render tab bar
      new_buf_ref = Quillex.Structs.BufState.BufRef.generate(new_buf)

      updated_buffers = Enum.map(state.buffers, fn b ->
        if b.uuid == new_buf.uuid, do: new_buf_ref, else: b
      end)

      new_active = if state.active_buf && state.active_buf.uuid == new_buf.uuid do
        new_buf_ref
      else
        state.active_buf
      end

      old_state = state
      new_state = %{state | buffers: updated_buffers, active_buf: new_active}

      new_graph = QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

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
  defp show_status(scene, message, severity) when is_binary(message) do
    ref = make_ref()
    Process.send_after(self(), {:clear_status_message, ref}, 5_000)
    old_state = scene.assigns.state
    new_state = %{old_state | status_message: message, status_severity: severity, status_ref: ref}
    new_graph = QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)
    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)
    {:noreply, new_scene}
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
        {:ok, new_buf} = Quillex.Buffer.BufferManager.call_buffer(buf_ref, {:action, [:save]})
        scene = maybe_update_dirty_state(scene, new_buf)
        {:noreply, scene}
    end
  end

  # ===========================================================================
  # Private Helpers - Editor Settings
  # ===========================================================================

  # Updates editor settings (word wrap, line numbers) and re-renders.
  # This syncs the TextField to the buffer first, then rebuilds with new settings.
  defp update_editor_settings(scene, new_state) do
    # With buffer_backed mode, just get cursor position from buffer (no sync needed)
    cursor_pos = get_buffer_cursor(scene)

    # Get first visible line for scroll preservation during word wrap toggle
    first_visible_line = get_first_visible_line(scene)

    # Update the IconMenu checkmarks to reflect new state
    new_menus = QuillEx.RootScene.Renderizer.build_menus(new_state)
    # put_child sends message to child but returns :ok, not scene
    Scenic.Scene.put_child(scene, :icon_menu, {:update_menus, new_menus})

    # Add cursor position and first visible line for restoration after re-render
    new_state = if cursor_pos do
      Map.put(new_state, :_restore_cursor, cursor_pos)
    else
      new_state
    end

    new_state = if first_visible_line do
      Map.put(new_state, :_restore_first_visible_line, first_visible_line)
    else
      new_state
    end

    # Reuse existing graph to preserve component PIDs and avoid race conditions
    old_state = scene.assigns.state
    new_graph = QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

    # Remove the temporary restore keys from state
    final_state = new_state
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

    # Get the word under cursor from TextField to pre-fill search
    initial_query = case Scenic.Scene.fetch_child(scene, :buffer_pane) do
      {:ok, [%TFState{} = tf_state]} ->
        TFState.word_at_cursor(tf_state) || ""
      _ ->
        ""
    end

    old_state = scene.assigns.state

    # If search bar is already showing and we're toggling replace mode, just update replace
    if old_state.show_search_bar and replace_mode do
      new_state = %{old_state | show_replace: true}
      new_graph = QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

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
    new_state = %{old_state |
      show_search_bar: true,
      search_query: initial_query,
      show_replace: replace_mode
    }

    # Reuse existing graph to preserve component PIDs and avoid race conditions
    new_graph = QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    # Blur the buffer pane so keystrokes go to SearchBar, not TextField
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
    new_state = %{scene.assigns.state |
      show_search_bar: false,
      show_replace: false,
      search_query: "",
      search_current_match: 0,
      search_total_matches: 0
    }

    # Clear search in TextField
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, :clear_search})

    # Reuse existing graph to preserve component PIDs and avoid race conditions
    old_state = scene.assigns.state
    new_graph = QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    # Refocus the buffer pane
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
    graph = scene.assigns.graph
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
    default_filename = case scene.assigns.state.active_buf do
      nil -> "untitled.txt"
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
          _ -> "untitled.txt"
        end
    end

    # Add the file picker component in save mode
    graph = scene.assigns.graph
      |> ScenicWidgets.FilePicker.add_to_graph(
        %{
          frame: new_state.frame,
          start_path: System.user_home!(),
          mode: :save,
          filename: default_filename
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
    graph = scene.assigns.graph
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
    graph = scene.assigns.graph
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
  # The BufRef stored in scene state is a cached snapshot and can be stale:
  # in buffer_backed mode the TextField writes directly to Buffer.Process and
  # RootScene is NOT subscribed to {:buffers, uuid} updates, so dirty? flips
  # in Buffer.Process without the cache being refreshed. Fresh-read here so
  # the decision uses the authoritative dirty state.
  defp try_close_buffer(scene, %Quillex.Structs.BufState.BufRef{} = buf_ref) do
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

  # Fresh-read the BufRef from Buffer.Process. The authoritative dirty? flag
  # lives in the buffer's own GenServer state — the copy in scene.assigns is a
  # cached snapshot from the last time RootScene actively applied an action.
  defp refresh_buf_ref(%Quillex.Structs.BufState.BufRef{} = buf_ref) do
    {:ok, buf_state} = Quillex.Buffer.Process.fetch_buf(buf_ref)
    Quillex.Structs.BufState.BufRef.generate(buf_state)
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

      %Quillex.Structs.BufState.BufRef{dirty?: true} = buf_ref ->
        new_state = %{state | show_unsaved_prompt: true, pending_close_buf_ref: buf_ref}
        {:show_prompt, buf_ref, new_state}

      %Quillex.Structs.BufState.BufRef{} = buf_ref ->
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

  # Saves the current buffer to a new file path.
  defp save_buffer_as(scene, file_path) do
    case scene.assigns.state.active_buf do
      nil ->
        Logger.warning("No active buffer to save")
        {:noreply, scene}

      buf_ref ->
        Logger.info("Saving buffer as: #{file_path}")

        # Use the buffer's save_as action
        result = Quillex.Buffer.Process.save_as(buf_ref, file_path)
        Logger.info("save_as result: #{inspect(result)}")

        case result do
          {:ok, updated_buf} ->
            Logger.info("Successfully saved to: #{file_path}, new name: #{updated_buf.name}")

            # Generate a new BufRef with the updated name
            new_buf_ref = Quillex.Structs.BufState.BufRef.generate(updated_buf)

            # Update the buffers list with the new BufRef
            old_state = scene.assigns.state
            updated_buffers = Enum.map(old_state.buffers, fn b ->
              if b.uuid == buf_ref.uuid, do: new_buf_ref, else: b
            end)

            # Update state with new buffers list and active_buf
            new_state = %{old_state |
              buffers: updated_buffers,
              active_buf: new_buf_ref
            }

            # Re-render to update the tab bar with new filename
            new_graph = QuillEx.RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

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
