defmodule QuillEx.GUI.Components.EditPane do
  use Scenic.Component
  use ScenicWidgets.ScenicEventsDefinitions
  require Logger
  # alias QuillEx.GUI.Components.{TabSelector, TextPad}
  alias ScenicWidgets.{TabSelector, TextPad}
  alias ScenicWidgets.Core.Structs.Frame

  # TODO remove, this should come from the font or something
  @tab_selector_height 40

  def validate(%{frame: %Frame{} = _f} = data) do
    # Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
    {:ok, data}
  end

  def init(scene, args, opts) do
    Logger.debug("#{__MODULE__} initializing...")
    Process.register(self(), __MODULE__)

    QuillEx.Utils.PubSub.register(topic: :radix_state_change)

    {:ok, ibm_plex_mono_fm} = TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")

    init_scene =
      scene
      |> assign(frame: args.frame)
      |> assign(font_metrics: ibm_plex_mono_fm)
      |> assign(graph: Scenic.Graph.build())

    # NOTE: no push_graph...

    request_input(init_scene, [:key])

    {:ok, init_scene}
  end

  def handle_cast({:frame_reshape, new_frame}, scene) do
    # new_graph = scene.assigns.graph
    # |> Scenic.Graph.modify(:menu_background, &Scenic.Primitives.rect(&1, new_frame.size))

    # new_scene = scene
    # |> assign(graph: new_graph)
    # |> assign(frame: new_frame)
    # |> push_graph(new_graph)

    {:noreply, scene}
  end

  # Single buffer
  def handle_info(
        {:radix_state_change,
         %{buffers: [%{id: id, data: text, cursor: cursor_coords}], active_buf: id}},
        scene
      )
      when is_bitstring(text) do
    Logger.debug("drawing a single TextPad since we have only one buffer open!")

    new_graph =
      scene.assigns.graph
      |> Scenic.Graph.delete(:edit_pane)
      |> Scenic.Primitives.group(
        fn graph ->
          graph
          |> ScenicWidgets.TextPad.add_to_graph(
            %{
              # NOTE: We don't need to move the pane around (referened from the outer frame of the EditPane) because there's no TabSelector being rendered (this is the single-buffer case))
              frame: Frame.new(pin: {0, 0}, size: scene.assigns.frame.size),
              text: text,
              format_opts: %{
                alignment: :left,
                wrap_opts: {:wrap, :end_of_line},
                show_line_num?: false
              },
              font: %{
                size: 24,
                metrics: scene.assigns.font_metrics
              }
            },
            id: :text_pad
          )
        end,
        translate: scene.assigns.frame.pin,
        id: :edit_pane
      )

    new_scene =
      scene
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  # Multiple buffers (so we render TabSelector, and move the TextPad down a bit)
  def handle_info({:radix_state_change, %{buffers: buf_list} = new_state}, scene)
      when length(buf_list) >= 2 do
    Logger.debug(
      "drawing a TextPad which has been moved down a bit, to make room for a TabSelector"
    )

    [full_active_buffer] = buf_list |> Enum.filter(&(&1.id == new_state.active_buf))

    new_graph =
      scene.assigns.graph
      |> Scenic.Graph.delete(:edit_pane)
      |> Scenic.Primitives.group(
        fn graph ->
          graph
          |> TabSelector.add_to_graph(%{
            radix_state: new_state,
            width: scene.assigns.frame.dimensions.width,
            height: @tab_selector_height
          })
          |> TextPad.add_to_graph(
            %{
              frame: %{
                # REMINDER: We need to move the TextPad down a bit, to make room for the TabSelector
                pin: {0, @tab_selector_height},
                size:
                  {scene.assigns.frame.dimensions.width,
                   scene.assigns.frame.dimensions.height - @tab_selector_height}
              },
              data: full_active_buffer.data,
              cursor: full_active_buffer.cursor
            },
            id: :text_pad
          )
        end,
        translate: scene.assigns.frame.pin,
        id: :edit_pane
      )

    new_scene =
      scene
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_input(key, _context, scene) when key in @valid_text_input_characters do
    Logger.debug("#{__MODULE__} recv'd valid input: #{inspect(key)}")

    QuillEx.API.Buffer.active_buf()
    |> QuillEx.API.Buffer.modify({:insert, key |> key2string(), :at_cursor})

    {:noreply, scene}
  end

  # treat key repeats as a press
  def handle_input({:key, {key, @key_held, mods}}, id, scene) do
    handle_input({:key, {key, @key_pressed, mods}}, id, scene)
  end

  def handle_input({:key, {key, @key_released, mods}}, id, scene) do
    Logger.debug("#{__MODULE__} ignoring key_release: #{inspect(key)}")
    {:noreply, scene}
  end

  def handle_input(key, id, scene) when key in [@left_shift] do
    Logger.debug("#{__MODULE__} ignoring key: #{inspect(key)}")
    {:noreply, scene}
  end

  def handle_input(@backspace_key, _context, scene) do
    QuillEx.API.Buffer.active_buf()
    |> QuillEx.API.Buffer.modify({:backspace, 1, :at_cursor})

    {:noreply, scene}
  end

  # def handle_input({:key, {key, _dont_care, _dont_care_either}}, _context, scene) do
  #     Logger.debug "#{__MODULE__} ignoring key: #{inspect key}"
  #     {:noreply, scene}
  # end
end