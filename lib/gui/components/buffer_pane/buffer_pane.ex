defmodule Quillex.GUI.Components.BufferPane do
  @moduledoc """
  BufferPane component - wraps ScenicWidgets.TextField from scenic-widget-contrib.

  ## Input Mode Configuration

  BufferPane supports different input modes via the `:input_mode` option:

  ### `:direct` (default)
  TextField handles all keyboard input directly. Good for standalone editors
  where BufferPane is the primary input target.

  ### `:external`
  TextField does NOT handle input. The parent application routes input through
  its own system (e.g., Fluxus) and updates the buffer. TextField just renders.

  ### `:buffer_backed`
  TextField handles input and directly communicates with Buffer.Process via PubSub.
  This mode provides live syncing between TextField state and Buffer state.

  ## Architecture

  - **:direct mode**: TextField handles input → emits events → BufferPane syncs to Buffer
  - **:external mode**: App handles input → updates Buffer → PubSub → BufferPane re-renders
  - **:buffer_backed mode**: TextField handles input → updates Buffer directly → PubSub sync

  ## Options

  - `:frame` (required) - Widgex.Frame for positioning
  - `:buf_ref` (required) - Reference to Buffer.Process
  - `:font` (required) - Font configuration
  - `:input_mode` - `:direct` (default), `:external`, or `:buffer_backed`
  - `:mode` - `:multi_line` (default) or `:single_line`
  - `:focused` - Boolean, auto-focus on mount
  - `:active?` - Boolean, whether editing is enabled
  """

  use Scenic.Component
  alias Quillex.GUI.Components.BufferPane
  alias ScenicWidgets.TextField
  require Logger

  def validate(
        %{
          frame: %Widgex.Frame{} = frame,
          buf_ref: %Quillex.Structs.BufState.BufRef{} = buf_ref,
          font: %Quillex.Structs.BufState.Font{} = font
        } = data
      ) do
    active? = Map.get(data, :active?, true)
    focused? = Map.get(data, :focused, false)
    mode = Map.get(data, :mode, :multi_line)
    input_mode = Map.get(data, :input_mode, :direct)
    show_line_numbers = Map.get(data, :show_line_numbers, true)
    state = BufferPane.State.new(data |> Map.merge(%{active?: active?}))

    {:ok, %{state: state, frame: frame, buf_ref: buf_ref, font: font, active?: active?, focused?: focused?, mode: mode, input_mode: input_mode, show_line_numbers: show_line_numbers}}
  end

  def init(scene, %{state: buf_pane_state, frame: frame, buf_ref: buf_ref, font: font, active?: active?, focused?: focused?, mode: mode, input_mode: input_mode, show_line_numbers: show_line_numbers}, _opts) do
    # Fetch initial buffer state
    {:ok, buf} = Quillex.Buffer.Process.fetch_buf(buf_ref)

    # Subscribe to buffer updates (for external changes)
    Quillex.Utils.PubSub.subscribe(topic: {:buffers, buf.uuid})

    # Prepare TextField configuration
    text_field_data = %{
      frame: frame,
      initial_text: Enum.join(buf.data, "\n"),
      mode: mode,
      input_mode: input_mode,
      wrap_mode: :none,  # No word wrap - enables horizontal scrolling for long lines
      show_line_numbers: show_line_numbers,
      editable: active?,
      focused: focused?,
      # Pass the buffer UUID as buffer_id so the TextField's semantic metadata
      # identifies which buffer this pane displays. SemanticHelpers.find_text_buffer/2
      # uses this to distinguish between multiple open buffers.
      buffer_id: buf.uuid,
      font: %{
        name: font.name,
        size: font.size,
        metrics: font.metrics
      },
      colors: %{
        text: :white,
        background: :medium_slate_blue,
        cursor: :white,
        line_numbers: {255, 255, 255, 85},
        border: {80, 80, 100, 180},
        focused_border: {255, 215, 0}
      },
      cursor_mode: :cursor,
      viewport_buffer_lines: 5,
      id: :text_field
    }

    # Add buffer_backed mode specific configuration if needed
    text_field_data = if input_mode == :buffer_backed do
      Map.merge(text_field_data, %{
        buffer_controller: get_buffer_pid(buf_ref),
        buffer_topic: {:buffers, buf.uuid}
      })
    else
      text_field_data
    end

    # Build graph with TextField
    graph =
      Scenic.Graph.build()
      |> TextField.add_to_graph(
        text_field_data,
        id: :text_field,
        translate: {0, 0}
      )

    init_scene =
      scene
      |> assign(graph: graph)
      |> assign(state: buf_pane_state)
      |> assign(frame: frame)
      |> assign(buf: buf)
      |> assign(buf_ref: buf_ref)
      |> assign(font: font)
      |> assign(active?: active?)
      |> push_graph(graph)

    {:ok, init_scene}
  end

  # TextField emits events when text changes - we sync to BufferProcess
  def handle_event({:text_changed, :text_field, new_text}, _from, scene) do
    Logger.debug("BufferPane: text changed, syncing to BufferProcess")

    # Convert text back to lines
    new_lines = String.split(new_text, "\n")

    # Update buffer process with new content
    updated_buf = %{scene.assigns.buf | data: new_lines, dirty?: true}

    {:noreply, assign(scene, buf: updated_buf)}
  end

  # TextField focus events
  def handle_event({:focus_gained, :text_field}, _from, scene) do
    Logger.debug("BufferPane: gained focus")
    {:noreply, scene}
  end

  def handle_event({:focus_lost, :text_field}, _from, scene) do
    Logger.debug("BufferPane: lost focus")
    {:noreply, scene}
  end

  # Clipboard events from TextField
  def handle_event({:clipboard_copy, :text_field, text}, _from, scene) do
    Logger.debug("BufferPane: copy #{String.length(text)} chars")
    {:noreply, scene}
  end

  def handle_event({:clipboard_cut, :text_field, text}, _from, scene) do
    Logger.debug("BufferPane: cut #{String.length(text)} chars")
    {:noreply, scene}
  end

  def handle_event({:clipboard_paste_requested, :text_field}, _from, scene) do
    Logger.debug("BufferPane: paste requested")
    {:noreply, scene}
  end

  def handle_event({:save_requested, :text_field, _text}, _from, scene) do
    Logger.debug("BufferPane: Ctrl+S pressed, save requested")
    {:noreply, scene}
  end

  # Enter pressed in single-line mode - bubble up to parent
  def handle_event({:enter_pressed, :text_field, text}, _from, scene) do
    Logger.debug("BufferPane: Enter pressed, text: #{String.slice(text, 0, 50)}...")
    GenServer.cast(scene.parent, {__MODULE__, :enter_pressed, scene.assigns.buf_ref, text})
    {:noreply, scene}
  end

  # Escape pressed - bubble up to parent
  def handle_event({:escape_pressed, :text_field}, _from, scene) do
    Logger.debug("BufferPane: Escape pressed")
    GenServer.cast(scene.parent, {__MODULE__, :escape_pressed, scene.assigns.buf_ref})
    {:noreply, scene}
  end

  # Catch-all for unexpected events - continue propagation so events like
  # {:replace_mode_requested, id} and {:find_requested, id} bubble up to RootScene.
  def handle_event(event, _from, scene) do
    Logger.debug("BufferPane: propagating unhandled event #{inspect(event)} to parent")
    {:cont, event, scene}
  end

  # Handle buffer state updates from PubSub (external changes)
  def handle_info({:buf_state_changes, new_buf}, %{assigns: %{buf: %{uuid: buf_uuid}}} = scene) do
    if new_buf.uuid == buf_uuid do
      # Extract the primary cursor position
      cursor_pos = case new_buf.cursors do
        [cursor | _] -> {cursor.line, cursor.col}
        _ -> {1, 1}  # Default if no cursors
      end

      Logger.debug("[BUFFER_PANE] Received buffer update via PubSub, syncing to TextField - cursor: #{inspect(cursor_pos)}")

      new_text = Enum.join(new_buf.data, "\n")
      Logger.debug("[BUFFER_PANE] Syncing text content and cursor position to TextField")

      # Sync both text content AND cursor position
      Scenic.Scene.put_child(scene, :text_field, new_text)
      Scenic.Scene.put_child(scene, :text_field, {:set_cursor, cursor_pos})

      {:noreply, assign(scene, buf: new_buf)}
    else
      {:noreply, scene}
    end
  end

  def handle_info(_msg, scene) do
    {:noreply, scene}
  end

  # ============================================================
  # EXTERNAL CONTROL API
  # ============================================================

  @doc """
  Handle external put commands - e.g., clear the text.
  """
  def handle_put(:clear, scene) do
    Logger.debug("BufferPane: clearing text")
    Scenic.Scene.put_child(scene, :text_field, "")
    {:noreply, scene}
  end

  # Forward actions from RootScene to TextField
  def handle_put({:action, action}, scene) do
    Logger.debug("BufferPane: forwarding action #{inspect(action)} to TextField")
    Scenic.Scene.put_child(scene, :text_field, {:action, action})
    {:noreply, scene}
  end

  def handle_put(:blur, scene) do
    Logger.debug("BufferPane: blurring TextField")
    Scenic.Scene.put_child(scene, :text_field, :blur)
    {:noreply, scene}
  end

  def handle_put(:focus, scene) do
    Logger.debug("BufferPane: focusing TextField")
    Scenic.Scene.put_child(scene, :text_field, :focus)
    {:noreply, scene}
  end

  def handle_put(msg, scene) do
    Logger.debug("BufferPane: unhandled put #{inspect(msg)}")
    {:noreply, scene}
  end

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
