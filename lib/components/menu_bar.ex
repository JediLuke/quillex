defmodule QuillEx.Scenic.Component.MenuBar do
    @moduledoc """
    The MenuBar component, which is permenently rendered along the top of QuillEx.

    ## Examples
    
    ```
    iex> graph
    iex> |> menu_bar()
    ```
    """
    use Scenic.Component, has_children: true
    alias Scenic.{Scene, ViewPort}
    alias Scenic.Component.Input.Caret
    alias Scenic.Primitive.Style.Theme
    alias QuillEx.Utils
    import Scenic.Primitives
  

    @menubar_height 64
    @button_size 0.72

    @buffer_around_button 

    @doc false
    def info(data) do
      "MenuBar failed to initialize - but MenuBar can accept any params!?"
    end
  
    @doc false
    def verify(_) do
      {:ok, %{}}
    end
  
    def verify(_), do: :invalid_data
  
    @doc false
    def init(_params, opts) do

      graph =
        Scenic.Graph.build()
        |> add_specs_to_graph([
             rect_spec(
                  {Utils.vp_width(opts[:viewport]), @menubar_height},
                  fill: {150, 100, 150}),
             Scenic.Components.button_spec(
                   "",
                   id: :new_file,
                   width: @button_size*@menubar_height,
                   height: @button_size*@menubar_height,
                   radius: 6,
                   # fill: {196, 202, 206},
                   # stroke: {2, :black},
                   theme: :info,
                   translate: {buffer_around_button(), buffer_around_button()})
        ])

      state = %{
        graph: graph,
        viewport: opts[:viewport]
      }

      {:ok, state, push: graph}
    end


    def filter_event({:click, :new_file}, _from, state) do
        #TODO need to figure out how we work this... based on state?
        ViewPort.set_root(state.viewport, {QuillEx.Scene.SingleFile, state})
        {:halt, state}
    end


    defp buffer_around_button do
        ((1-@button_size)/2)*@menubar_height
    end
end