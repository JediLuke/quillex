defmodule QuillEx.Scene.Editor do
  use Scenic.Scene
  alias QuillEx.Utils
  alias QuillEx.ScenicComponent.MenuBar
  import Scenic.Primitives
  import Scenic.Components
  import QuillEx.ScenicComponent.TextPad, only: [{:text_pad, 3}]
  require Logger


  def init(_, opts) do

    graph =
      Scenic.Graph.build()
      |> MenuBar.add_to_graph()

    #NOTE: This process holds the root state of the entire application

    state = %{
      graph: graph,               # the %Scenic.Graph{} currenly being rendered
      viewport: opts[:viewport],
      buffer_list: [],            # holds a reference to each open buffer
      active_buffer: nil,         # holds a reference to the `active` buffer
    }

    {:ok, state, push: graph}
  end

  def filter_event({:menubar, {:click, :new_file}}, _from, %{buffer_list: [], active_buffer: nil} = state) do

    new_buffer_list = [
      %{
        title: "untitled",
        saved?: false,
        lines: [""],
        path: nil
      }
    ]

    active_buffer = 0 # first entry in the buffer_list, indexed at 0 because that's what Enum wants

    new_graph =
      Scenic.Graph.build()
      |> text_pad(
           [""],
           id: :pad,
           width: Utils.vp_width(state.viewport),
           height: Utils.vp_height(state.viewport) - MenuBar.height(),
           translate: {0, MenuBar.height()})
      |> MenuBar.add_to_graph()

    new_state =
      state
      |> Map.replace!(:graph, new_graph)
      |> Map.replace!(:buffer_list, new_buffer_list)
      |> Map.replace!(:active_buffer, active_buffer)

    {:noreply, new_state, push: new_state.graph}
  end

  def filter_event({:menubar, {:click, :new_file}}, _from, state) do
    Logger.warn "Unable to open a new blank file."
    {:noreply, state}
  end

  # def handle_info({:DOWN, _ref, :process, {QuillEx.MainExecutiveProcess, _address}, reason}, state) do
  #   raise "A scene crashed due to it's MONITOR of MEP"
  #   {:noreply, state}
  # end

end