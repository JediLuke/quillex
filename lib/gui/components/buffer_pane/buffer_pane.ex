defmodule Quillex.GUI.Components.BufferPane do
  use Scenic.Component
  use ScenicWidgets.ScenicEventsDefinitions
  alias Quillex.GUI.Components.BufferPane
  require Logger
  # This creates a text-input interface like Notepad/Gedit.

  # As much as possible, this Component is just a "thin" rendering component.
  # ALl logic like editing the component is done at a "higher level" and then
  # the graphics are updated by casting messages to this Component.

  # ## TODO future features

  # - line wrap
  # - make arrow navigation work for non-monospaced fonts
  # - mouse click to move cursor
  # - selectable text using mouse
  # - cut & paste?
  # - Automtically scroll when the cursor movement goes close to the edge of the screen
  # - Mouse-draggable scroll bars

  #   # Scroll wrapping - for this, I can go ahead with existing text (which wraps),
  #   # but treat it as larger than another container. However, ultimately
  #   # I want to be able to disable the scroll-wrapping talked about above,
  #   # so that I can render  continuous line, & potentially scroll it

  #   # Other unimplemented cases: Max 1 line height (e.g. KommandBuffer)

  #   # TODO handle mutiple cursors

  #    #TODO place cursor in last line of the TextPad when we pass in some text...

  @no_limits_to_tomorrow "The only limit to our realization of tomorrow is our doubts of today\n\n- Frankin D. Roosevelt"

  def validate(
        %{
          frame: %Widgex.Frame{} = frame,
          buf_ref: %Quillex.Structs.BufState.BufRef{} = buf_ref,
          font: %Quillex.Structs.BufState.Font{} = _font
        } = data
      ) do

    active? = Map.get(data, :active?, true)


    state = BufferPane.State.new(data |> Map.merge(%{active?: active?}))
    Logger.info "Buffer: #{inspect buf_ref} is state?: #{inspect state}"

    {:ok, %{state: state, frame: frame, buf_ref: buf_ref, active?: active?}}
  end

  def init(scene, %{state: buf_pane_state, frame: frame, buf_ref: buf_ref, active?: active?}, _opts) do
    # I think it's more in-keeping with the Zen of scenic to go and fetch state upon our boot,
    # since that keeps the integrity our gui thread even if the external data source if bad,
    # plus I think it's more efficient in terms of data transfer to just get it once rather than pass it around everywhere (maybe?)
    {:ok, buf} = Quillex.Buffer.Process.fetch_buf(buf_ref)

    graph =
      BufferPane.Renderizer.render(Scenic.Graph.build(), scene, frame, buf_pane_state, buf)

    init_scene =
      scene
      |> assign(graph: graph)
      |> assign(state: buf_pane_state)
      |> assign(frame: frame)
      |> assign(buf: buf)
      |> assign(buf_ref: buf_ref)
      |> assign(active?: active?)
      |> push_graph(graph)

    # Registry.register(Quillex.BufferRegistry, __MODULE__, nil)
    Logger.info "REGISTERING BUFFER AS #{buf.uuid}"

    # SHIT ok here we go, we used to register buffer panes according to theri buffer... now we cant !! cause we only make ONE buffer pane & modify it !!
    Quillex.Utils.PubSub.subscribe(topic: {:buffers, buf.uuid})

    {:ok, init_scene}
  end

  def handle_cast({:user_input, input}, scene) do
    # the GUI component converts raw user input to actions, directly on this layer,
    # which are then passed back up the component tree for processing
    Logger.info "BUF GOT input #{inspect input}"
    case BufferPane.UserInputHandler.handle(scene.assigns, input) do
      :ignore ->
        {:noreply, scene}

      actions when is_list(actions) ->
        Logger.info("BufferPane: Generated actions #{inspect(actions)}, casting to parent")
        cast_parent(scene, {__MODULE__, :action, scene.assigns.buf_ref, actions})
        {:noreply, scene}

      actn when is_tuple(actn) ->
        raise "A handler function is ont returning a list. Returned: #{inspect actn}"

      # {%BufferPane.State{} = new_buf_pane_state, :ignore} ->
      #   {:noreply, scene |> assign(state: new_buf_pane_state)}

      # {%BufferPane.State{} = new_buf_pane_state, actions} when is_list(actions) ->
      #   cast_parent(scene, {__MODULE__, :action, scene.assigns.buf_ref, actions})
      #   {:noreply, scene |> assign(state: new_buf_pane_state)}
    end
  end

  def handle_cast({:frame_change, %Widgex.Frame{} = frame}, %{assigns: %{frame: frame}} = scene) do
    # frame didn't change (same variable name means we bound to both vars, they are equal) so do nothing
    IO.puts "#{__MODULE__} ignoring frame change..."
    {:noreply, scene}
  end

  def handle_cast(
    {:state_change, %Quillex.Structs.BufState.BufRef{uuid: uuid, name: name, mode: mode} = new_buf},
    %{assigns: %{buf_ref: %{uuid: uuid, name: name, mode: mode}}} = scene
  ) do
    # no actual changes were made so we can discard this msg (all variables bind on same name)
    IO.puts "#{__MODULE__} ignoring buf_ref change... #{inspect new_buf}"
    {:noreply, scene}
  end

  def handle_cast(
    {:state_change, %Quillex.Structs.BufState.BufRef{uuid: uuid} = new_buf_ref},
    %{assigns: %{buf_ref: %{uuid: uuid}}} = scene
  ) do

    IO.puts "Expect to get to here for left buffer #{inspect new_buf_ref}"
    new_buf =
      %{scene.assigns.buf|name: new_buf_ref.name, mode: new_buf_ref.mode}

    new_graph =
      BufferPane.Renderizer.render(
        scene.assigns.graph,
        scene,
        scene.assigns.frame,
        scene.assigns.state,
        new_buf
      )

    new_scene =
      scene
      |> assign(graph: new_graph)
      |> assign(buf: new_buf)
      |> assign(buf_ref: new_buf_ref)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_cast(
    {:state_change, %Quillex.Structs.BufState.BufRef{uuid: new_uuid} = new_buf_ref},
    %{assigns: %{buf_ref: %{uuid: old_uuid}}} = scene
  ) when old_uuid != new_uuid do

    {:ok, new_buf} =
      Quillex.Buffer.BufferManager.get_live_buffer(new_buf_ref)
      # Quillex.Buffer.Process.fetch_buf(new_buf_ref)

    IO.inspect(new_buf)

    new_graph =
      BufferPane.Renderizer.render(
        scene.assigns.graph,
        scene,
        scene.assigns.frame,
        scene.assigns.state,
        new_buf
      )

    new_scene =
      scene
      |> assign(graph: new_graph)
      |> assign(buf: new_buf)
      |> assign(buf_ref: new_buf_ref)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  # REMOVED: This pattern matching was incorrectly ignoring valid state changes
  # The real state change handler below should handle ALL buffer updates

  def handle_cast(
    {:state_change, %Quillex.Structs.BufState{uuid: uuid} = new_buf},
    %{assigns: %{buf_ref: %{uuid: uuid}}} = scene
  ) do

    new_graph =
      BufferPane.Renderizer.render(
        scene.assigns.graph,
        scene,
        scene.assigns.frame,
        scene.assigns.state,
        new_buf
      )

    new_scene =
      scene
      |> assign(graph: new_graph)
      |> assign(buf: new_buf)
      |> push_graph(new_graph)

    # TODO maybe this code below  will work to optimize not calling push_graph if we dont need to? Is this a significant saving?
    # if new_scene.assigns.graph != scene.assigns.graph do
    #   new_scene = push_graph(new_scene, new_scene.assigns.graph)
    # end

    {:noreply, new_scene}
  end

  def handle_cast({:state_change, invalid}, scene) do
    Logger.info "INVALID STATE CHANGE #{inspect invalid}"
    {:noreply, scene}
  end

  # this is the one we get from the broadcast, just route it to the cast handler
  def handle_info({:buf_state_changes, %Quillex.Structs.BufState{} = new_buf}, scene) do
    handle_cast({:state_change, new_buf}, scene)
  end

  def handle_info({:user_input, input}, scene) do
    handle_cast({:user_input, input}, scene)
  end
end

# TODO
# def handle_cast({:frame_reshape, new_frame}, scene)

#   def handle_cast(
#         {:scroll_limits, %{inner: %{width: _w, height: _h}, frame: _f} = new_scroll_state},
#         scene
#       ) do
#     # update the RadixStore, without broadcasting the changes,
#     # so we can keep accurate calculations for scrolling
#     radix_store(scene)

#     radix_store(scene).get()
#     |> radix_reducer(scene).change_editor_scroll_state(new_scroll_state)
#     |> radix_store(scene).put()

#     {:noreply, scene}
#   end

# end

# # def handle_cast({:redraw, %{scroll: _delta}}, %{assigns: %{percentage: p}} = scene) when p >= 1 do
# #   IO.puts "NO SCRTOLL"
# #   {:noreply, scene}
# # end

# # def handle_cast({:redraw, %{scroll: {delta_x, delta_y}}}, scene) do

# #   IO.puts "GOT SCROLL!?!???"

# #   diff = (1-scene.assigns.percentage) * scene.assigns.frame.dimensions.width

# #   {x_diff, y_diff} = new_scroll_acc =
# #     Scenic.Math.Vector2.add(scene.assigns.scroll_acc, {delta_x*x_scroll_factor, delta_y*@scroll_speed})
# #     |> calc_ceil(@min_position_cap)
# #     # |> IO.inspect(label: "NEW SCROLL")

# #   if abs(x_diff) >= diff do
# #     IO.puts "YESSS - DONT SCROLLLLLLL"
# #     IO.inspect x_diff, label: "XDIF"
# #     IO.inspect diff, label: "DIF"

# #     {:noreply, scene}

# #   else
# #     IO.puts "NOOOOO"
# #     IO.inspect x_diff, label: "XDIF"
# #     IO.inspect diff, label: "DIF"

# #     new_graph =scene.assigns.graph |> Scenic.Graph.modify(
# #       {__MODULE__, scene.assigns.id, :text_area},
# #       &Scenic.Primitives.update_opts(&1, translate: new_scroll_acc)
# #     )

# #     #TODO update scroll bar

# #     new_scene = scene
# #     |> assign(graph: new_graph)
# #     |> push_graph(new_graph)

# #     {:noreply, new_scene}

# #   end
# # end

# # NOTE: This doesn't work simply because when we type a msg, the line of
# # text doesn't get updated before we try to calculate the cursor position
# # def handle_cast({:redraw, %{cursor: cursor}}, scene) do
# #   # text = Enum.at(scene.assigns.data, cursor.line-1)

# #   {:ok, [pid]} = child(scene, {:line, cursor.line})
# #   {:ok, text} = GenServer.call(pid, :get_text)

# #   {x_pos, _cursor_line_num} =
# #       FontMetrics.position_at(text, cursor.col-1, scene.assigns.state.font.size, scene.assigns.state.font.metrics)

# #   new_cursor =
# #     {
# #       (scene.assigns.state.margin.left + x_pos),
# #       (scene.assigns.state.margin.top + ((cursor.line-1) * line_height(scene.assigns)))
# #     }

# #   {:ok, [pid]} = child(scene, {:cursor, 1})
# #   GenServer.cast(pid, {:move, new_cursor})

# #   {:noreply, scene}
# # end

# # GenServer.cast(pid, {:redraw, %{data: active_BufferPane.data, cursor: hd(active_BufferPane.cursors)}})
# # GenServer.cast(pid, {:redraw, %{scroll_acc: active_BufferPane.scroll_acc}})
# # def handle_update(%{text: t, cursor: %Cursor{} = c, scroll_acc: s} = data, opts, scene) when is_bitstring(t) do

# # TODO ok this is stupid, we need to go through validate/1 to use this, even though most of it is a waste of time...

# # def handle_update(%{text: t, cursor: c, scroll_acc: s} = data, opts, scene) when is_bitstring(t) do
# #   # IO.puts "HAND:ING UPDATEEEE"
# #   # lines = String.split(t, @newline_char)
# #   GenServer.cast(self(), %{data: t, cursor: c})
# #   GenServer.cast(self(), %{scroll_acc: s})
# #   {:noreply, scene}
# # end

# # def handle_cast({:redraw, %{data: text} = args}, scene) when is_bitstring(text) do
# #   Logger.debug "converting text input to list of lines..."
# #   lines = String.split(text, @newline_char)
# #   GenServer.cast(self(), {:redraw, Map.put(args, :data, lines)})
# #   {:noreply, scene}
# # end

# # defmodule Scenic.Component.Input.TextField do
# #     @moduledoc """
# #     Add a text field input to a graph
# #     ## Data
# #     `initial_value`
# #     * `initial_value` - is the string that will be the starting value
# #     ## Messages
# #     When the text in the field changes, it sends an event message to the host
# #     scene in the form of:
# #     `{:value_changed, id, value}`
# #     ## Styles
# #     Text fields honor the following styles
# #     * `:hidden` - If `false` the component is rendered. If `true`, it is skipped.
# #     The default is `false`.
# #     * `:theme` - The color set used to draw. See below. The default is `:dark`
# #     ## Additional Options
# #     Text fields honor the following list of additional options.
# #     * `:filter` - Adding a filter option restricts which characters can be
# #     entered into the text_field component. The value of filter can be one of:
# #       * `:all` - Accept all characters. This is the default
# #       * `:number` - Any characters from "0123456789.,"
# #       * `"filter_string"` - Pass in a string containing all the characters you
# #       will accept
# #       * `function/1` - Pass in an anonymous function. The single parameter will
# #       be the character to be filtered. Return `true` or `false` to keep or reject
# #       it.
# #     * `:hint` - A string that will be shown (greyed out) when the entered value
# #     of the component is empty.
# #     * `:hint_color` - any [valid color](Scenic.Primitive.Style.Paint.Color.html).
# #     * `:type` - Can be one of the following options:
# #       * `:all` - Show all characters. This is the default.
# #       * `:password` - Display a string of '*' characters instead of the value.
# #     * `:width` - set the width of the control.
# #     ## Theme
# #     Text fields work well with the following predefined themes: `:light`, `:dark`
# #     To pass in a custom theme, supply a map with at least the following entries:
# #     * `:text` - the color of the text
# #     * `:background` - the background of the component
# #     * `:border` - the border of the component
# #     * `:focus` - the border while the component has focus
# #     ## Usage
# #     You should add/modify components via the helper functions in
# #     [`Scenic.Components`](Scenic.Components.html#text_field/3)
# #     ## Examples
# #         graph
# #         |> text_field("Sample Text", id: :text_id, translate: {20,20})
# #         graph
# #         |> text_field(
# #           "", id: :pass_id, type: :password, hint: "Enter password", translate: {20,20}
# #         )
# #     """

# #     @default_hint ""
# #     @default_hint_color :grey
# #     @default_font :roboto_mono
# #     @default_font_size 20
# #     @char_width 12
# #     @inset_x 10

# #     @default_type :text
# #     @default_filter :all

# #     @default_width @char_width * 24
# #     @default_height @default_font_size * 1.5

# #     @input_capture [:cursor_button, :codepoint, :key]

# #     # --------------------------------------------------------
# #     @doc false
# #     @impl Scenic.Scene
# #     def init(scene, value, opts) do
# #       id = opts[:id]

# #       # theme is passed in as an inherited style
# #       theme =
# #         (opts[:theme] || Theme.preset(:dark))
# #         |> Theme.normalize()

# #       # get the text_field specific opts
# #       hint = opts[:hint] || @default_hint
# #       width = opts[:width] || opts[:w] || @default_width
# #       height = opts[:height] || opts[:h] || @default_height
# #       type = opts[:type] || @default_type
# #       filter = opts[:filter] || @default_filter
# #       hint_color = opts[:hint_color] || @default_hint_color

# #       index = String.length(value)

# #       display = display_from_value(value, type)

# #       caret_v = -trunc((height - @default_font_size) / 4)

# #       scene =
# #         assign(
# #           scene,
# #           graph: nil,
# #           theme: theme,
# #           width: width,
# #           height: height,
# #           value: value,
# #           display: display,
# #           hint: hint,
# #           hint_color: hint_color,
# #           index: index,
# #           char_width: @char_width,
# #           focused: false,
# #           type: type,
# #           filter: filter,
# #           id: id,
# #           caret_v: caret_v
# #         )

# #       graph =
# #         Graph.build(
# #           font: @default_font,
# #           font_size: @default_font_size,
# #           scissor: {width, height}
# #         )
# #         |> rect(
# #           {width, height},
# #           # fill: :clear,
# #           fill: theme.background,
# #           stroke: {2, theme.border},
# #           id: :border,
# #           input: :cursor_button
# #         )
# #         |> group(
# #           fn g ->
# #             g
# #             |> text(
# #               @default_hint,
# #               fill: hint_color,
# #               t: {0, @default_font_size},
# #               id: :text
# #             )
# #             |> Caret.add_to_graph(height, id: :caret)
# #           end,
# #           t: {@inset_x, 2}
# #         )
# #         |> update_text(display, scene.assigns)
# #         |> update_caret(display, index, caret_v)

# #       scene =
# #         scene
# #         |> assign(graph: graph)
# #         |> push_graph(graph)

# #       {:ok, scene}
# #     end

# #     @impl Scenic.Component
# #     def bounds(_data, opts) do
# #       width = opts[:width] || opts[:w] || @default_width
# #       height = opts[:height] || opts[:h] || @default_height
# #       {0, 0, width, height}
# #     end

# #     # ============================================================================

# #     # --------------------------------------------------------
# #     # to be called when the value has changed
# #     defp update_text(graph, "", %{hint: hint, hint_color: hint_color}) do
# #       Graph.modify(graph, :text, &text(&1, hint, fill: hint_color))
# #     end

# #     defp update_text(graph, value, %{theme: theme}) do
# #       Graph.modify(graph, :text, &text(&1, value, fill: theme.text))
# #     end

# #     # ============================================================================

# #     # --------------------------------------------------------
# #     defp update_caret(graph, value, index, caret_v) do
# #       str_len = String.length(value)

# #       # double check the postition
# #       index =
# #         cond do
# #           index < 0 -> 0
# #           index > str_len -> str_len
# #           true -> index
# #         end

# #       # calc the caret position
# #       x = index * @char_width

# #       # move the caret
# #       Graph.modify(graph, :caret, &update_opts(&1, t: {x, caret_v}))
# #     end

# #     # --------------------------------------------------------
# #     defp capture_focus(%{assigns: %{focused: false, graph: graph, theme: theme}} = scene) do
# #       # capture the input
# #       capture_input(scene, @input_capture)

# #       # start animating the caret
# #       cast_children(scene, :start_caret)

# #       # show the caret
# #       graph =
# #         graph
# #         |> Graph.modify(:caret, &update_opts(&1, hidden: false))
# #         |> Graph.modify(:border, &update_opts(&1, stroke: {2, theme.focus}))

# #       # update the state
# #       scene
# #       |> assign(focused: true, graph: graph)
# #       |> push_graph(graph)
# #     end

# #     # --------------------------------------------------------
# #     defp release_focus(%{assigns: %{focused: true, graph: graph, theme: theme}} = scene) do
# #       # release the input
# #       release_input(scene)

# #       # stop animating the caret
# #       cast_children(scene, :stop_caret)

# #       # hide the caret
# #       graph =
# #         graph
# #         |> Graph.modify(:caret, &update_opts(&1, hidden: true))
# #         |> Graph.modify(:border, &update_opts(&1, stroke: {2, theme.border}))

# #       # update the state
# #       scene
# #       |> assign(focused: false, graph: graph)
# #       |> push_graph(graph)
# #     end

# #     # --------------------------------------------------------
# #     # get the text index from a mouse position. clap to the
# #     # beginning and end of the string
# #     defp index_from_cursor({x, _}, value) do
# #       # account for the text inset
# #       x = x - @inset_x

# #       # get the max index
# #       max_index = String.length(value)

# #       # calc the new index
# #       d = x / @char_width
# #       i = trunc(d)
# #       i = i + round(d - i)
# #       # clamp the result
# #       cond do
# #         i < 0 -> 0
# #         i > max_index -> max_index
# #         true -> i
# #       end
# #     end

# #     # --------------------------------------------------------
# #     defp display_from_value(value, :password) do
# #       String.to_charlist(value)
# #       |> Enum.map(fn _ -> @password_char end)
# #       |> to_string()
# #     end

# #     defp display_from_value(value, _), do: value

# #     # ============================================================================
# #     # User input handling - get the focus

# #     # --------------------------------------------------------
# #     # unfocused click in the text field
# #     @doc false
# #     @impl Scenic.Scene
# #     def handle_input(
# #           {:cursor_button, {:btn_left, 1, _, _}} = inpt,
# #           :border,
# #           %{assigns: %{focused: false}} = scene
# #         ) do
# #       handle_input(inpt, :border, capture_focus(scene))
# #     end

# #     # --------------------------------------------------------
# #     # focused click in the text field
# #     def handle_input(
# #           {:cursor_button, {:btn_left, 1, _, pos}},
# #           :border,
# #           %{assigns: %{focused: true, value: value, index: index, graph: graph, caret_v: caret_v}} =
# #             scene
# #         ) do
# #       {index, graph} =
# #         case index_from_cursor(pos, value) do
# #           ^index ->
# #             {index, graph}

# #           i ->
# #             # reset_caret the caret blinker
# #             cast_children(scene, :reset_caret)

# #             # move the caret
# #             {i, update_caret(graph, value, i, caret_v)}
# #         end

# #       scene =
# #         scene
# #         |> assign(index: index, graph: graph)
# #         |> push_graph(graph)

# #       {:noreply, scene}
# #     end

# #     # --------------------------------------------------------
# #     # focused click outside the text field
# #     def handle_input(
# #           {:cursor_button, {:btn_left, 1, _, _}},
# #           _id,
# #           %{assigns: %{focused: true}} = scene
# #         ) do
# #       {:cont, release_focus(scene)}
# #     end

# #     # ignore other button press events
# #     def handle_input({:cursor_button, {_, _, _, _}}, _id, scene) do
# #       {:noreply, scene}
# #     end

# #     # ============================================================================
# #     # control keys

# #     # --------------------------------------------------------
# #     def handle_input(
# #           {:key, {:key_left, 1, _}},
# #           _id,
# #           %{assigns: %{index: index, value: value, graph: graph, caret_v: caret_v}} = scene
# #         ) do
# #       # move left. clamp to 0
# #       {index, graph} =
# #         case index do
# #           0 ->
# #             {0, graph}

# #           i ->
# #             # reset_caret the caret blinker
# #             cast_children(scene, :reset_caret)
# #             # move the caret
# #             i = i - 1
# #             {i, update_caret(graph, value, i, caret_v)}
# #         end

# #       scene =
# #         scene
# #         |> assign(index: index, graph: graph)
# #         |> push_graph(graph)

# #       {:noreply, scene}
# #     end

# #     # --------------------------------------------------------
# #     def handle_input(
# #           {:key, {:key_right, 1, _}},
# #           _id,
# #           %{assigns: %{index: index, value: value, graph: graph, caret_v: caret_v}} = scene
# #         ) do
# #       # the max position for the caret
# #       max_index = String.length(value)

# #       # move left. clamp to 0
# #       {index, graph} =
# #         case index do
# #           ^max_index ->
# #             {index, graph}

# #           i ->
# #             # reset the caret blinker
# #             cast_children(scene, :reset_caret)

# #             # move the caret
# #             i = i + 1
# #             {i, update_caret(graph, value, i, caret_v)}
# #         end

# #       scene =
# #         scene
# #         |> assign(index: index, graph: graph)
# #         |> push_graph(graph)

# #       {:noreply, scene}
# #     end

# #     # --------------------------------------------------------
# #     def handle_input({:key, {:key_pageup, 1, mod}}, id, state) do
# #       handle_input({:key, {:key_home, 1, mod}}, id, state)
# #     end

# #     def handle_input(
# #           {:key, {:key_home, 1, _}},
# #           _id,
# #           %{assigns: %{index: index, value: value, graph: graph, caret_v: caret_v}} = scene
# #         ) do
# #       # move left. clamp to 0
# #       {index, graph} =
# #         case index do
# #           0 ->
# #             {index, graph}

# #           _ ->
# #             # reset the caret blinker
# #             cast_children(scene, :reset_caret)

# #             # move the caret
# #             {0, update_caret(graph, value, 0, caret_v)}
# #         end

# #       scene =
# #         scene
# #         |> assign(index: index, graph: graph)
# #         |> push_graph(graph)

# #       {:noreply, scene}
# #     end

# #     # --------------------------------------------------------
# #     def handle_input({:key, {:key_pagedown, 1, mod}}, id, scene) do
# #       handle_input({:key, {:key_end, 1, mod}}, id, scene)
# #     end

# #     def handle_input(
# #           {:key, {:key_end, 1, _}},
# #           _id,
# #           %{assigns: %{index: index, value: value, graph: graph, caret_v: caret_v}} = scene
# #         ) do
# #       # the max position for the caret
# #       max_index = String.length(value)

# #       # move left. clamp to 0
# #       {index, graph} =
# #         case index do
# #           ^max_index ->
# #             {index, graph}

# #           _ ->
# #             # reset the caret blinker
# #             cast_children(scene, :reset_caret)

# #             # move the caret
# #             {max_index, update_caret(graph, value, max_index, caret_v)}
# #         end

# #       scene =
# #         scene
# #         |> assign(index: index, graph: graph)
# #         |> push_graph(graph)

# #       {:noreply, scene}
# #     end

# #     # --------------------------------------------------------
# #     # ignore backspace if at index 0
# #     def handle_input({:key, {:key_backspace, 1, _}}, _id, %{assigns: %{index: 0}} = scene),
# #       do: {:noreply, scene}

# #     # handle backspace
# #     def handle_input(
# #           {:key, {:key_backspace, 1, _}},
# #           _id,
# #           %{
# #             assigns: %{
# #               graph: graph,
# #               value: value,
# #               index: index,
# #               type: type,
# #               id: id,
# #               caret_v: caret_v
# #             }
# #           } = scene
# #         ) do
# #       # reset_caret the caret blinker
# #       cast_children(scene, :reset_caret)

# #       # delete the char to the left of the index
# #       value =
# #         String.to_charlist(value)
# #         |> List.delete_at(index - 1)
# #         |> to_string()

# #       display = display_from_value(value, type)

# #       # send the value changed event
# #       send_parent_event(scene, {:value_changed, id, value})

# #       # move the index
# #       index = index - 1

# #       # update the graph
# #       graph =
# #         graph
# #         |> update_text(display, scene.assigns)
# #         |> update_caret(display, index, caret_v)

# #       scene =
# #         scene
# #         |> assign(
# #           graph: graph,
# #           value: value,
# #           display: display,
# #           index: index
# #         )
# #         |> push_graph(graph)

# #       {:noreply, scene}
# #     end

# #     # --------------------------------------------------------
# #     def handle_input(
# #           {:key, {:key_delete, 1, _}},
# #           _id,
# #           %{
# #             assigns: %{
# #               graph: graph,
# #               value: value,
# #               index: index,
# #               type: type,
# #               id: id
# #             }
# #           } = scene
# #         ) do
# #       # ignore delete if at end of the field
# #       case index < String.length(value) do
# #         false ->
# #           {:noreply, scene}

# #         true ->
# #           # reset the caret blinker
# #           cast_children(scene, :reset_caret)

# #           # delete the char at the index
# #           value =
# #             String.to_charlist(value)
# #             |> List.delete_at(index)
# #             |> to_string()

# #           display = display_from_value(value, type)

# #           # send the value changed event
# #           send_parent_event(scene, {:value_changed, id, value})

# #           # update the graph (the caret doesn't move)
# #           graph = update_text(graph, display, scene.assigns)

# #           scene =
# #             scene
# #             |> assign(
# #               graph: graph,
# #               value: value,
# #               display: display,
# #               index: index
# #             )
# #             |> push_graph(graph)

# #           {:noreply, scene}
# #       end
# #     end

# #     # --------------------------------------------------------
# #     defp do_handle_codepoint(
# #            char,
# #            %{
# #              assigns: %{
# #                graph: graph,
# #                value: value,
# #                index: index,
# #                type: type,
# #                id: id,
# #                caret_v: caret_v
# #              }
# #            } = scene
# #          ) do
# #       # reset the caret blinker
# #       cast_children(scene, :reset_caret)

# #       # insert the char into the string at the index location
# #       {left, right} = String.split_at(value, index)
# #       value = Enum.join([left, char, right])
# #       display = display_from_value(value, type)

# #       # send the value changed event
# #       send_parent_event(scene, {:value_changed, id, value})

# #       # advance the index
# #       index = index + String.length(char)

# #       # update the graph
# #       graph =
# #         graph
# #         |> update_text(display, scene.assigns)
# #         |> update_caret(display, index, caret_v)

# #       scene =
# #         scene
# #         |> assign(
# #           graph: graph,
# #           value: value,
# #           display: display,
# #           index: index
# #         )
# #         |> push_graph(graph)

# #       {:noreply, scene}
# #     end

# #     # --------------------------------------------------------
# #     @doc false
# #     @impl Scenic.Scene
# #     def handle_get(_, %{assigns: %{value: value}} = scene) do
# #       {:reply, value, scene}
# #     end

# #     @doc false
# #     @impl Scenic.Scene
# #     def handle_put(v, %{assigns: %{value: value}} = scene) when v == value do
# #       # no change
# #       {:noreply, scene}
# #     end

# #     def handle_put(
# #           text,
# #           %{
# #             assigns: %{
# #               graph: graph,
# #               id: id,
# #               index: index,
# #               caret_v: caret_v,
# #               type: type
# #             }
# #           } = scene
# #         )
# #         when is_bitstring(text) do
# #       send_parent_event(scene, {:value_changed, id, text})

# #       display = display_from_value(text, type)

# #       # if the index is beyond the end of the string, move it back into range
# #       max_index = String.length(display)

# #       index =
# #         case index > max_index do
# #           true -> max_index
# #           false -> index
# #         end

# #       graph =
# #         graph
# #         |> update_text(display, scene.assigns)
# #         |> update_caret(display, index, caret_v)

# #       scene =
# #         scene
# #         |> assign(graph: graph, value: text)
# #         |> push_graph(graph)

# #       {:noreply, scene}
# #     end

# #     def handle_put(v, %{assigns: %{id: id}} = scene) do
# #       Logger.warn(
# #         "Attempted to put an invalid value on TextField id: #{inspect(id)}, value: #{inspect(v)}"
# #       )

# #       {:noreply, scene}
# #     end

# #     @doc false
# #     @impl Scenic.Scene
# #     def handle_fetch(_, %{assigns: %{value: value}} = scene) do
# #       {:reply, {:ok, value}, scene}
# #     end
# #   end
