defmodule Quillex.GUI.Components.BufferPane do
  @moduledoc """
  BufferPane component - wraps ScenicWidgets.TextField from scenic-widget-contrib.

  QuillEx is a simple Notepad-style editor (no Vim modes), so we use TextField
  in direct input mode where it handles all editing, and we sync changes back
  to the BufferProcess.

  The architecture:
  - TextField handles: all input, rendering, cursor positioning, text editing
  - BufferPane handles: syncing TextField changes to BufferProcess
  - BufferProcess handles: buffer state persistence, undo/redo (future)
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
    mode = Map.get(data, :mode, :multi_line)  # :multi_line or :single_line
    state = BufferPane.State.new(data |> Map.merge(%{active?: active?}))

    {:ok, %{state: state, frame: frame, buf_ref: buf_ref, font: font, active?: active?, focused?: focused?, mode: mode}}
  end

  def init(scene, %{state: buf_pane_state, frame: frame, buf_ref: buf_ref, font: font, active?: active?, focused?: focused?, mode: mode}, _opts) do
    # Fetch initial buffer state
    {:ok, buf} = Quillex.Buffer.Process.fetch_buf(buf_ref)

    # Subscribe to buffer updates (for external changes)
    Quillex.Utils.PubSub.subscribe(topic: {:buffers, buf.uuid})

    # Prepare TextField configuration using DIRECT input mode
    # TextField will handle all input itself
    text_field_data = %{
      frame: frame,
      initial_text: Enum.join(buf.data, "\n"),
      mode: mode,  # :multi_line for editors, :single_line for Kommander
      input_mode: :direct,  # TextField handles all input directly!
      show_line_numbers: true,
      editable: active?,
      focused: focused?,  # Auto-focus when requested (e.g., Kommander)
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
        border: :clear,
        focused_border: :clear
      },
      cursor_mode: :cursor,
      viewport_buffer_lines: 5,
      id: :text_field  # ID for receiving events
    }

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
    # TODO: We need to create an action for this, or directly update
    # For now, let's just update our local buf state
    updated_buf = %{scene.assigns.buf | data: new_lines, dirty?: true}

    # Notify buffer process of change
    # Quillex.Buffer.Process.update_content(scene.assigns.buf_ref, new_lines)

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
    # TextField already handled the clipboard, nothing to do
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

  def handle_event({:save_requested, :text_field, text}, _from, scene) do
    Logger.debug("BufferPane: Ctrl+S pressed, save requested")
    # TODO: Trigger save
    {:noreply, scene}
  end

  # Enter pressed in single-line mode - bubble up to parent (e.g., Kommander)
  def handle_event({:enter_pressed, :text_field, text}, _from, scene) do
    Logger.debug("BufferPane: Enter pressed, text: #{String.slice(text, 0, 50)}...")
    # Bubble this event up to the parent scene
    # The parent (e.g., Kommander) will handle execution
    GenServer.cast(scene.parent, {__MODULE__, :enter_pressed, scene.assigns.buf_ref, text})
    {:noreply, scene}
  end

  # Escape pressed - bubble up to parent (e.g., Kommander to close)
  def handle_event({:escape_pressed, :text_field}, _from, scene) do
    Logger.debug("BufferPane: Escape pressed")
    GenServer.cast(scene.parent, {__MODULE__, :escape_pressed, scene.assigns.buf_ref})
    {:noreply, scene}
  end

  # Catch-all for unexpected events
  def handle_event(event, _from, scene) do
    Logger.debug("BufferPane: unhandled event #{inspect(event)}")
    {:noreply, scene}
  end

  # Handle buffer state updates from PubSub (external changes)
  def handle_info({:buffer_updated, buf_uuid, new_buf}, %{assigns: %{buf: %{uuid: buf_uuid}}} = scene) do
    Logger.debug("BufferPane: external buffer update received")

    # Update TextField with new content
    # For now, we'll just update our state - full sync would require rebuilding TextField
    {:noreply, assign(scene, buf: new_buf)}
  end

  def handle_info(_msg, scene) do
    {:noreply, scene}
  end

  # ============================================================
  # EXTERNAL CONTROL API
  # ============================================================

  @doc """
  Handle external put commands - e.g., clear the text.
  Uses Scenic's put protocol to send to child TextField.
  """
  def handle_put(:clear, scene) do
    Logger.debug("BufferPane: clearing text")
    # Send empty string to TextField to clear it
    Scenic.Scene.put_child(scene, :text_field, "")
    {:noreply, scene}
  end

  def handle_put(msg, scene) do
    Logger.debug("BufferPane: unhandled put #{inspect(msg)}")
    {:noreply, scene}
  end
end
