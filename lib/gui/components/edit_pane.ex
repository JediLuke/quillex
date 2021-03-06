defmodule QuillEx.GUI.Components.EditPane do
  use Scenic.Component
  use ScenicWidgets.ScenicEventsDefinitions
  require Logger
  alias ScenicWidgets.{TabSelector, TextPad}
  alias ScenicWidgets.Core.Structs.Frame

  # TODO remove, this should come from the font or something
  @tab_selector_height 40

  #TODO cursors

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
          |> TextPad.add_to_graph(enhance_args(scene, %{
                text: text,
                frame: full_screen_buffer(scene)
          }))
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

    [active_buffer] = buf_list |> Enum.filter(&(&1.id == new_state.active_buf))
    tab_list = buf_list |> Enum.map(& &1.id)

    font = %{
      name: :ibm_plex_mono,
      size: 20,
      metrics: scene.assigns.font_metrics
    }

    theme = %{
      active: {58, 94, 201},
      background: {72, 122, 252},
      border: :light_grey,
      focus: :cornflower_blue,
      highlight: :sandy_brown,
      text: :white,
      thumb: :cornflower_blue
    }

    new_graph =
      scene.assigns.graph
      |> Scenic.Graph.delete(:edit_pane)
      |> Scenic.Primitives.group(
        fn graph ->
          graph
          |> TabSelector.add_to_graph(%{
                frame: Frame.new(width: scene.assigns.frame.dimensions.width, height: @tab_selector_height),
                theme: theme,
                tab_list: tab_list,
                active: active_buffer.id,
                font: font,
                menu_item: %{width: 220}
          })
          |> TextPad.add_to_graph(enhance_args(scene, %{
                text: active_buffer.data,
                frame: full_screen_buffer(scene, tab_selector_visible?: true)
          #NOTE: We translate the box down here, on this level - not in the Component below (that just adjusts it's size)
          }), translate: {0, @tab_selector_height})
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

  def handle_event({:tab_clicked, tab_label}, _from, scene) do
    # Flamelex.Fluxus.action({MemexReducer, :new_tidbit})
    #TODO buffer.find, then Buffer.activate
    Logger.warn "TAB CLICKED"
    QuillEx.API.Buffer.activate(tab_label)
    {:noreply, scene}
  end

  def handle_event({:hover_tab, tab_label}, _from, scene) do
    # Flamelex.Fluxus.action({MemexReducer, :new_tidbit})
    #TODO buffer.find, then Buffer.activate
    Logger.warn "TAB HOVERED"
    {:noreply, scene}
  end

  def handle_event({:value_changed, :text_pad, new_value}, _from, scene) do
    Logger.warn "TEXT PAD CHANGED"
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

  def handle_input({:key, {key, _dont_care, _dont_care_either}}, _context, scene) do
      Logger.debug "#{__MODULE__} ignoring key: #{inspect key}"
      {:noreply, scene}
  end

  # To make the TextPad's rendering code more palatable, I bunched
  # up a bunch of their arguments into this function call
  def enhance_args(scene, other_args) do
    Map.merge(other_args, %{
      id: :text_pad,
      mode: :edit,
      format_opts: %{
        alignment: :left,
        wrap_opts: :no_wrap,
        scroll_opts: :all_directions,
        show_line_num?: true
      },
      font: %{
        name: :ibm_plex_mono,
        size: 24,
        metrics: scene.assigns.font_metrics
      }
    })
  end
  
  # Return a %Frame{} that's full-screen, depending on whether or not we
  # need to adjust for adding a TabSelector
  def full_screen_buffer(scene), do: full_screen_buffer(scene, tab_selector_visible?: false)
  def full_screen_buffer(scene, tab_selector_visible?: tab_selector_visible?) do
    #NOTE: If the TabSelector is visible, we need to reduce the height of
    #      a full-screen buffer, to make room for the TabSelector. In the
    #      single-buffer case, we don't need to make any height reduction
    height_reduction =
      if tab_selector_visible?, do: @tab_selector_height, else: 0
    
    Frame.new(
      #NOTE: We translate the box down here, on this level, so use {0, 0} for the pin
      pin: {0, 0},
      size:
        {scene.assigns.frame.dimensions.width,
        scene.assigns.frame.dimensions.height - height_reduction})
  end

end








    #NOTE: Don't handle events here, just let them bubble-up to the
    #      parent scene - https://hexdocs.pm/scenic/Scenic.Scene.html#module-event-filtering
    # def handle_event({:tab_clicked, tab_label}, _from, scene) do
    #     {:noreply, scene}
    # end

    # #NOTE: This case is where there's just one buffer open
    # def handle_info({:radix_state_change, %{buffers: [%{id: _id, data: _d}]} = new_state}, scene) do
    #     Logger.debug "#{__MODULE__} de-activating/ignoring the TabSelector, as we don't get shown if there's only one buffer"

    #     new_graph = scene.assigns.graph
    #     |> Scenic.Graph.delete(:tab_selector)

    #     new_scene = scene
    #     |> assign(graph: new_graph)
    #     |> push_graph(new_graph)

    #     {:noreply, new_scene}
    # end

    # #TODO right now, this re-draws every time there's a RadixState update - we ought to compare it against what we have, & only update/broadcast if it really changed
    # # This case takes us from :inactive -> 2 buffers
    # def handle_info({:radix_state_change, %{buffers: buf_list, active_buf: active_buf} = new_state}, scene) when length(buf_list) >= 2 and length(buf_list) <= 7 do
    #     #Logger.debug "#{__MODULE__} ignoring radix_state: #{inspect new_state}, scene_state: #{inspect scene.assigns.state}}"
    #     Logger.debug "#{__MODULE__} drawing a 2-tab TabSelector --"

    #     {:ok, ibm_plex_mono_fm} = TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")
    #     fm = ibm_plex_mono_fm #TODO get this once and keep hold of it in the state

    #     render_tabs = fn(init_graph) ->
    #         {final_graph, _final_offset} = 
    #             buf_list
    #             # |> Enum.map(fn %{id: id} -> id end) # we only care about id's...
    #             |> Enum.with_index()
    #             |> Enum.reduce({init_graph, _init_offset = 0}, fn {%{id: label}, index}, {graph, offset} ->
    #                     label_width = @menu_width #TODO - either fixed width, or flex width (adapts to size of label)
    #                     item_width  = label_width+@left_margin
    #                     carry_graph = graph
    #                     |> SingleTab.add_to_graph(%{
    #                             label: label,
    #                             ref: label,
    #                             active?: label == active_buf,
    #                             margin: 10,
    #                             font: %{
    #                                 size: @tab_font_size,
    #                                 ascent: FontMetrics.ascent(@tab_font_size, fm),
    #                                 descent: FontMetrics.descent(@tab_font_size, fm),
    #                                 metrics: fm},
    #                             frame: %{
    #                                 pin: {offset, 0}, #REMINDER: coords are like this, {x_coord, y_coord}
    #                                 size: {item_width, 40} #TODO dont hard-code
    #                             }}) 
    #                     {carry_graph, offset+item_width}
    #             end)

    #         final_graph

    #     end

    #     new_graph = scene.assigns.graph
    #     |> Scenic.Graph.delete(:tab_selector)
    #     |> Scenic.Primitives.group(fn graph ->
    #         graph
    #         |> Scenic.Primitives.rect({scene.assigns.frame.width, 40}, fill: scene.assigns.theme.background)
    #         |> render_tabs.()
    #       end, [
    #          id: :tab_selector
    #       ])

    #     new_scene = scene
    #     |> assign(graph: new_graph)
    #     # |> assign(state: %{buffers: buf_list})
    #     |> push_graph(new_graph)

    #     {:noreply, new_scene}
    # end

