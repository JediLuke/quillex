defmodule QuillEx.Scene.RootScene.RenderTool do
  # alias QuillEx.GUI.Components.{Editor, SplashScreen}
  # alias ScenicWidgets.Core.Structs.Frame
  # alias ScenicWidgets.Core.Utils.FlexiFrame
  alias QuillEx.Fluxus.Structs.RadixState
  alias Widgex.Structs.Frame

  def render(
        %Scenic.ViewPort{} = vp,
        %RadixState{} = radix_state
      ) do
    # menu_bar_frame =
    #   Frame.new(vp, {:standard_rule, frame: 1, linemark: radix_state.menu_bar.height})

    # editor_frame =
    #   Frame.new(vp, {:standard_rule, frame: 2, linemark: radix_state.menu_bar.height})

    # |> render_menubar(%{frame: menubar_f, radix_state: radix_state})

    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph |> render_components(vp, radix_state)
      end,
      id: :quillex_root
    )
  end

  def render_components(graph, _vp, %{components: []} = _radix_state) do
    graph
  end

  def render_components(graph, vp, radix_state) do
    # new_graph = graph

    framestack = Frame.stack(vp, radix_state.layout)

    # |> ScenicWidgets.FrameBox.draw(%{frame: hd(editor_f), color: :blue})
    # |> Editor.add_to_graph(args |> Map.merge(%{app: QuillEx}), id: :editor)
    if length(radix_state.components) != length(framestack) do
      raise "length of components and framestack must match"
    end

    component_frames = Enum.zip(radix_state.components, framestack)

    graph |> do_render_components(component_frames)
  end

  defp do_render_components(graph, []) do
    graph
  end

  defp do_render_components(graph, [{nil, _f} | rest]) do
    # if component is nil just draw nothing
    graph |> do_render_components(rest)
  end

  # defp do_render_components(graph, [%Widgex.Component{} = c | rest]) when is_struct(c) do
  defp do_render_components(graph, [{c, %Frame{} = f} | rest]) when is_struct(c) do
    graph
    |> c.__struct__.add_to_graph({c, f})
    |> do_render_components(rest)
  end

  defp do_render_components(graph, [{sub_stack, sub_frame_stack} | rest])
       when is_list(sub_stack) and is_list(sub_frame_stack) do
    if length(sub_stack) != length(sub_frame_stack) do
      raise "length of (sub!) components and framestack must match"
    end

    sub_component_frames = Enum.zip(sub_stack, sub_frame_stack)

    graph
    |> do_render_components(sub_component_frames)
    |> do_render_components(rest)
  end

  # def render_menubar(graph, %{frame: frame, radix_state: radix_state}) do
  #   menubar_args = %{
  #     frame: frame,
  #     menu_map: calc_menu_map(radix_state),
  #     font: radix_state.desktop.menu_bar.font
  #   }

  #   graph
  #   # |> ScenicWidgets.FrameBox.draw(%{frame: menubar_f, color: :red})
  #   |> ScenicWidgets.MenuBar.add_to_graph(menubar_args, id: :menu_bar)
  # end

  # def calc_menu_map(%{editor: %{buffers: []}}) do
  #   [
  #     {:sub_menu, "Buffer",
  #      [
  #        {"new", &QuillEx.API.Buffer.new/0}
  #      ]},
  #     {:sub_menu, "View",
  #      [
  #        {"toggle line nums", fn -> raise "no" end},
  #        {"toggle file tray", fn -> raise "no" end},
  #        {"toggle tab bar", fn -> raise "no" end},
  #        {:sub_menu, "font",
  #         [
  #           {:sub_menu, "primary font",
  #            [
  #              {"ibm plex mono",
  #               fn ->
  #                 QuillEx.Fluxus.RadixStore.get()
  #                 |> QuillEx.Reducers.RadixReducer.change_font(:ibm_plex_mono)
  #                 |> QuillEx.Fluxus.RadixStore.put()
  #               end},
  #              {"roboto",
  #               fn ->
  #                 QuillEx.Fluxus.RadixStore.get()
  #                 |> QuillEx.Reducers.RadixReducer.change_font(:roboto)
  #                 |> QuillEx.Fluxus.RadixStore.put()
  #               end},
  #              {"roboto mono",
  #               fn ->
  #                 QuillEx.Fluxus.RadixStore.get()
  #                 |> QuillEx.Reducers.RadixReducer.change_font(:roboto_mono)
  #                 |> QuillEx.Fluxus.RadixStore.put()
  #               end},
  #              {"iosevka",
  #               fn ->
  #                 QuillEx.Fluxus.RadixStore.get()
  #                 |> QuillEx.Reducers.RadixReducer.change_font(:iosevka)
  #                 |> QuillEx.Fluxus.RadixStore.put()
  #               end},
  #              {"source code pro",
  #               fn ->
  #                 QuillEx.Fluxus.RadixStore.get()
  #                 |> QuillEx.Reducers.RadixReducer.change_font(:source_code_pro)
  #                 |> QuillEx.Fluxus.RadixStore.put()
  #               end},
  #              {"fira code",
  #               fn ->
  #                 QuillEx.Fluxus.RadixStore.get()
  #                 |> QuillEx.Reducers.RadixReducer.change_font(:fira_code)
  #                 |> QuillEx.Fluxus.RadixStore.put()
  #               end},
  #              {"bitter",
  #               fn ->
  #                 QuillEx.Fluxus.RadixStore.get()
  #                 |> QuillEx.Reducers.RadixReducer.change_font(:bitter)
  #                 |> QuillEx.Fluxus.RadixStore.put()
  #               end}
  #            ]},
  #           {"make bigger",
  #            fn ->
  #              QuillEx.Fluxus.RadixStore.get()
  #              |> QuillEx.Reducers.RadixReducer.change_font_size(:increase)
  #              |> QuillEx.Fluxus.RadixStore.put()
  #            end},
  #           {"make smaller",
  #            fn ->
  #              QuillEx.Fluxus.RadixStore.get()
  #              |> QuillEx.Reducers.RadixReducer.change_font_size(:decrease)
  #              |> QuillEx.Fluxus.RadixStore.put()
  #            end}
  #         ]}
  #      ]},
  #     {:sub_menu, "Help",
  #      [
  #        {"about QuillEx", &QuillEx.API.Misc.makers_mark/0}
  #      ]}
  #   ]
  # end

  # def calc_menu_map(%{editor: %{buffers: buffers}})
  #     when is_list(buffers) and length(buffers) >= 1 do
  #   # NOTE: Here what we do is just take the base menu (with no open buffers)
  #   # and add the new buffer menu in to it using Enum.map

  #   base_menu = calc_menu_map(%{editor: %{buffers: []}})

  #   open_bufs_sub_menu =
  #     buffers
  #     |> Enum.map(fn %{id: {:buffer, name} = buf_id} ->
  #       # NOTE: Wrap this call in it's closure so it's a function of arity /0
  #       {name, fn -> QuillEx.API.Buffer.activate(buf_id) end}
  #     end)

  #   Enum.map(base_menu, fn
  #     {:sub_menu, "Buffer", base_buffer_menu} ->
  #       {:sub_menu, "Buffer",
  #        base_buffer_menu ++ [{:sub_menu, "open-buffers", open_bufs_sub_menu}]}

  #     other_menu ->
  #       other_menu
  #   end)
  # end
end
