defmodule QuillEx.RootScene do
  use Scenic.Scene
  alias QuillEx.RootScene
  alias Quillex.GUI.RadixReducer
  alias Quillex.Buffer.BufferManager
  require Logger

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

    state = RootScene.State.new(%{
      frame: Widgex.Frame.new(scene.viewport),
      buffers: buffers
    })

    # need to pass in scene so we can cast to children, even though we would never do that during init
    # On init, old_state is nil (no previous state)
    graph = RootScene.Renderizer.render(Scenic.Graph.build(), scene, nil, state)

    scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    Process.register(self(), __MODULE__)
    Quillex.Utils.PubSub.subscribe(topic: :qlx_events)

    # TextField handles its own input in :direct mode, so we only request viewport events
    request_input(scene, [:viewport])

    {:ok, scene}
  end

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
      new_graph = RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

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

  def handle_input(input, _context, scene) do
    # TextField in :direct mode handles its own input, so we don't need to forward
    # This catch-all is kept for any unexpected input events
    # Logger.debug("RootScene received unexpected input: #{inspect(input)}")
    {:noreply, scene}
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
        Logger.error "Couldn't compute action #{inspect actions}. #{inspect reason}"
        {:reply, {:error, reason}, scene}
    end
  end

  def handle_call({:action, a}, _from, scene) do
    # wrap singular actions in a list and push through the multi-action pipeline anyway
    handle_call({:action, [a]}, nil, scene)
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
        Logger.error "Couldn't compute action #{inspect actions}. #{inspect reason}"
        raise "Couldn't compute action #{inspect actions}. #{inspect reason}"

        #TODO recovery idea - there is a possibility that we sometimes have a race condition
        # and that's why this happens, e.g. we open a buffer via BufferManager, BfrMgr is supposed
        # to broadcast out changes like "buffer opened" when it's done, but what if between that
        # happening someone came in here with an action like "open buffer x" which, technically
        # has been opened, but the msg hasn't got back to the GUI process yet cause, race condition

        # there's 2 ideas to make this more robust
        # 1- we could have a repetition here, if it failed, send the action back to ourself 50ms
        # from now, and try again. Then we need to keep track of state so we dont indefinitely keep retrying forever
        # 2- we could also listen to the pubsub broadcast channel from the API, and make it
        # wait for acknowldge ment that way
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

    # Flamelex.Fluxus.action()

    # interact with the Buffer state to apply the actions - thisd is equivalent to Fluxus
    # Applying actions to buffer
    {:ok, new_buf} = Quillex.Buffer.BufferManager.call_buffer(buf_ref, {:action, actions})
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

    {:noreply, scene}
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
      new_graph = RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

      {new_state, new_graph}
    end)
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
    IO.puts("🔍 Search query changed (cast): \"#{query}\"")
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
    IO.puts("🔍 Search next (cast)")
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, :find_next})
    {:noreply, scene}
  end

  def handle_cast({:search_prev, _id}, scene) do
    IO.puts("🔍 Search previous (cast)")
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, :find_prev})
    {:noreply, scene}
  end

  def handle_cast({:search_close, _id}, scene) do
    IO.puts("🔍 Search bar closed (cast)")
    hide_search_bar(scene)
  end

  # if actions come in via PubSub they come in via handle_info, just convert to handle_cast
  def handle_info({:action, a}, scene) do
    handle_cast({:action, a}, scene)
  end

  def handle_info({:new_buffer_opened, %Quillex.Structs.BufState.BufRef{} = buf_ref}, scene) do
    new_state =
      scene.assigns.state
      # to be honest I dont understand how this is already been added here but I guess it has....
      # its cause when we start a new buffer, we do add it to the state of this process!

      # we _should_ check incase it hasn't been added I guess...

      # do we were adding it in both places sometimes, I had to cancel adding it in the mutator (which was calling new buffer in BNufrMgr)
      # and instead RootScene has to wait for the callback that it worked...

      # if Enum.any?(state.buffers, & &1.uuid == buf_ref.uuid) do
      #   Quillex.Utils.PubSub.broadcast(
      #       topic: :qlx_events,
      #       msg: {:action, {:activate_buffer, buf_ref}}
      #     )
      #   {:reply, {:ok, buf_ref}, state}
      # else
      #   raise "Could not find buffer: #{inspect buf_ref}"
      #   # do_start_new_buffer_process(state, buf_red)
      # end

      |> RootScene.Mutator.add_buffer(buf_ref)
      |> RootScene.Mutator.activate_buffer(buf_ref)

    # Reuse existing graph to preserve component PIDs and avoid race conditions
    old_state = scene.assigns.state
    new_graph = RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_info({:ubuntu_bar_button_clicked, button_id, button}, scene) do
    # UbuntuBar button clicked: #{button_id}"

    # Handle different button actions
    case button_id do
      :new_file ->
        # Create a new buffer
        handle_cast({:action, :new_buffer}, scene)

      :open_file ->
        # Open file functionality not implemented yet
        {:noreply, scene}

      :save_file ->
        # Save file functionality not implemented yet
        {:noreply, scene}

      :search ->
        # Search functionality not implemented yet
        {:noreply, scene}

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
        # Save file - not implemented yet
        {:noreply, scene}

      "save_as" ->
        # Show file picker in save mode
        show_file_picker_save(scene)

      "close" ->
        # Close the active buffer (no sync needed - buffer_backed mode)
        handle_cast({:action, :close_active_buffer}, scene)

      "undo" ->
        # Undo - send undo action to the buffer pane
        Scenic.Scene.put_child(scene, :buffer_pane, {:action, :undo})
        {:noreply, scene}

      "redo" ->
        # Redo - send redo action to the buffer pane
        Scenic.Scene.put_child(scene, :buffer_pane, {:action, :redo})
        {:noreply, scene}

      "cut" ->
        # Cut - not implemented yet
        {:noreply, scene}

      "copy" ->
        # Copy - not implemented yet
        {:noreply, scene}

      "paste" ->
        # Paste - not implemented yet
        {:noreply, scene}

      "find" ->
        # Find - show search bar
        IO.puts("🔍 Find menu clicked!")
        show_search_bar(scene)

      "find_next" ->
        # Find next match
        IO.puts("🔍 Find Next menu clicked!")
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
      # With buffer_backed mode, Buffer.Process is source of truth - no sync needed
      handle_cast({:action, {:close_buffer, buf_ref}}, scene)
    else
      Logger.warning("Could not find buffer for tab close: #{inspect(tab_id)}")
      {:noreply, scene}
    end
  end

  # Save file (Ctrl+S from TextField)
  def handle_event({:save_requested, _id, _text}, _from, scene) do
    # With buffer_backed mode, Buffer.Process already has current content - no sync needed
    # Save the buffer to disk
    case scene.assigns.state.active_buf do
      nil ->
        Logger.warning("No active buffer to save")
        {:noreply, scene}

      buf_ref ->
        Quillex.Buffer.BufferManager.call_buffer(buf_ref, {:action, [:save]})
        {:noreply, scene}
    end
  end

  # Find/Search (Ctrl+F from TextField)
  def handle_event({:find_requested, _id}, _from, scene) do
    IO.puts("🔍 find_requested event received - showing search bar")
    show_search_bar(scene)
  end

  # Search bar events - query changed
  def handle_event({:search_query_changed, _id, query}, _from, scene) do
    IO.puts("🔍 Search query changed: \"#{query}\"")
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
    IO.puts("🔍 Search next")
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, :find_next})
    {:noreply, scene}
  end

  # Search bar events - previous match
  def handle_event({:search_prev, _id}, _from, scene) do
    IO.puts("🔍 Search previous")
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, :find_prev})
    {:noreply, scene}
  end

  # Search bar events - close
  def handle_event({:search_close, _id}, _from, scene) do
    IO.puts("🔍 Search bar closed")
    hide_search_bar(scene)
  end

  # Search complete (from TextField after parallel search)
  def handle_event({:search_complete, _id, query, match_count}, _from, scene) do
    if match_count > 0 do
      IO.puts("✨ Found #{match_count} matches for \"#{query}\"")
    else
      IO.puts("❌ No matches found for \"#{query}\"")
    end

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
    IO.puts("🔍 Match #{current_idx + 1} of #{total}")

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

  # Catch-all for unhandled events
  def handle_event(event, _from, scene) do
    Logger.debug("Unhandled event: #{inspect(event)}")
    {:noreply, scene}
  end

  # ===========================================================================
  # Private Helpers - Editor Settings
  # ===========================================================================

  @doc """
  Updates editor settings (word wrap, line numbers) and re-renders.
  This syncs the TextField to the buffer first, then rebuilds with new settings.
  """
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
    new_graph = RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

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

  @doc """
  Shows the search bar and optionally pre-fills with word under cursor.
  """
  defp show_search_bar(scene) do
    alias ScenicWidgets.TextField.State, as: TFState

    # Get the word under cursor from TextField to pre-fill search
    initial_query = case Scenic.Scene.fetch_child(scene, :buffer_pane) do
      {:ok, [%TFState{} = tf_state]} ->
        TFState.word_at_cursor(tf_state) || ""
      _ ->
        ""
    end

    old_state = scene.assigns.state
    new_state = %{old_state |
      show_search_bar: true,
      search_query: initial_query
    }

    # Reuse existing graph to preserve component PIDs and avoid race conditions
    new_graph = RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    # Blur the buffer pane so keystrokes go to SearchBar, not TextField
    Scenic.Scene.put_child(new_scene, :buffer_pane, :blur)

    # If we have an initial query, perform search
    if String.length(initial_query) > 0 do
      IO.puts("🔍 Pre-filling search with: \"#{initial_query}\"")
      Scenic.Scene.put_child(new_scene, :search_bar, {:set_query, initial_query})
      Scenic.Scene.put_child(new_scene, :buffer_pane, {:action, {:search, initial_query}})
    end

    {:noreply, new_scene}
  end

  @doc """
  Hides the search bar and clears search state.
  """
  defp hide_search_bar(scene) do
    new_state = %{scene.assigns.state |
      show_search_bar: false,
      search_query: "",
      search_current_match: 0,
      search_total_matches: 0
    }

    # Clear search in TextField
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, :clear_search})

    # Reuse existing graph to preserve component PIDs and avoid race conditions
    old_state = scene.assigns.state
    new_graph = RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    # Refocus the buffer pane
    Scenic.Scene.put_child(new_scene, :buffer_pane, :focus)

    {:noreply, new_scene}
  end

  @doc """
  Performs search and updates state.
  """
  defp perform_search(scene, query, state) do
    # Send search action to TextField
    Scenic.Scene.put_child(scene, :buffer_pane, {:action, {:search, query}})

    new_scene = scene |> assign(state: state)
    {:noreply, new_scene}
  end

  # ===========================================================================
  # Private Helpers - File Picker
  # ===========================================================================

  @doc """
  Shows the file picker modal (for opening files).
  """
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

  @doc """
  Shows the file picker modal in save mode (for saving files).
  """
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

  @doc """
  Hides the file picker modal and optionally opens a file.
  """
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

  @doc """
  Hides the file picker modal and saves the current buffer to the specified path.
  """
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

  @doc """
  Saves the current buffer to a new file path.
  """
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
            new_graph = RootScene.Renderizer.render(scene.assigns.graph, scene, old_state, new_state)

            new_scene =
              scene
              |> assign(state: new_state)
              |> assign(graph: new_graph)
              |> push_graph(new_graph)

            # Refocus the buffer pane
            Scenic.Scene.put_child(new_scene, :buffer_pane, :focus)

            {:noreply, new_scene}

          {:error, reason} ->
            Logger.error("Failed to save file: #{inspect(reason)}")
            {:noreply, scene}

          other ->
            Logger.error("Unexpected save_as result: #{inspect(other)}")
            {:noreply, scene}
        end
    end
  end

  @doc """
  Opens a file and creates a new buffer for it.
  """
  defp open_file(scene, file_path) do
    Logger.info("Opening file: #{file_path}")

    case Quillex.API.FileAPI.open(file_path) do
      {:ok, %{buffer_ref: buf_ref, lines: lines, bytes: bytes}} ->
        Logger.info("Opened file with #{lines} lines, #{bytes} bytes")

        # The FileAPI.open already switches to the new buffer and broadcasts
        # the :new_buffer_opened message, so we just need to wait for that
        {:noreply, scene}

      {:error, reason} ->
        Logger.error("Failed to open file: #{reason}")
        {:noreply, scene}
    end
  end
end
