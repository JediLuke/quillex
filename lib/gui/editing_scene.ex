defmodule QuillEx.Scene.Default do
  use Scenic.Scene
  alias QuillEx.Utils
  alias QuillEx.ScenicComponent.MenuBar
  import Scenic.Primitives
  import Scenic.Components
  import QuillEx.ScenicComponent.TextPad, only: [{:text_pad, 3}]
  require Logger


  def init(_, opts) do

    # Process.monitor(QuillEx.MainExecutiveProcess)

    # {:ok, initial_text} = 
    #         GenServer.call(QuillEx.MainExecutiveProcess, :init_default_gui_scene)
  
    graph =
      Scenic.Graph.build()
      |> MenuBar.add_to_graph()

    state = %{
      graph: graph,               # the %Scenic.Graph{} currenly being rendered
      viewport: opts[:viewport],
      buffer_list: [],            # holds a reference to each open buffer
      active_buffer: nil,         # holds a reference to the `active` buffer
    }

    {:ok, state, push: graph}
  end

  def filter_event({:menubar, {:click, :new_file}}, _from, state) do
    IO.puts "\n\n\n\nHIEHIEHR\n\n\n\n\n"
    new_state = state |> open_new_blank_file()
    {:noreply, new_state, push: new_state.graph}
  end
  
  def handle_info({:DOWN, _ref, :process, {QuillEx.MainExecutiveProcess, _address}, reason}, state) do
    raise "A scene crashed due to it's MONITOR of MEP"
    {:noreply, state}
  end

  def open_new_blank_file(%{buffer_list: [], active_buffer: nil} = state) do
    
    new_graph =
      Scenic.Graph.build()
      |> text_pad(
           [""],
           id: :pad,
           width: Utils.vp_width(state.viewport),
           height: Utils.vp_height(state.viewport) - MenuBar.height(),
           translate: {0, MenuBar.height()})
      |> MenuBar.add_to_graph()

    new_buffer_list = [
      # %TextFile{}
      "BUBUB"
    ]

    active_buffer = 1

    %{state |
        graph: new_graph,
        buffer_list: new_buffer_list,
        active_buffer: active_buffer}
  end
end