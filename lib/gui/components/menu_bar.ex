defmodule QuillEx.ScenicComponent.MenuBar do
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
    alias QuillEx.Structs.TextFile
    import Scenic.Primitives
  

    @menubar_height 64
    @button_size 0.72

    @background {48, 48, 48} # {150, 100, 150}

    @doc false
    def info(data) do
      "MenuBar failed to initialize - but MenuBar can accept any params!?"
    end

    def height, do: @menubar_height
  
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
                  fill: @background),
             rrect_spec({@button_size*@menubar_height, @button_size*@menubar_height, 6},
                   stroke: {2, :white},
                   translate: {buffer_around_button(), buffer_around_button()}),
             Scenic.Components.button_spec(
               "",
                   id: :new_file,
                   width: @button_size*@menubar_height,
                   height: @button_size*@menubar_height,
                   radius: 6,
                   theme: :primary,
                   translate: {buffer_around_button(), buffer_around_button()}),
             # draw the new-file icon
             group_spec([
               line_spec({{0, 0}, {0, 0.6*@button_size*@menubar_height}}, stroke: {2, :black}),
               line_spec({{0, 0}, {0.4*@button_size*@menubar_height, 0}}, stroke: {2, :black}),
               line_spec({{0.4*@button_size*@menubar_height, 0}, {0.6*@button_size*@menubar_height, 0.2*@button_size*@menubar_height}}, stroke: {2, :black}),
               line_spec({{0.6*@button_size*@menubar_height, 0.2*@button_size*@menubar_height}, {0.6*@button_size*@menubar_height, 0.6*@button_size*@menubar_height}}, stroke: {2, :black}),
               line_spec({{0, 0.6*@button_size*@menubar_height}, {0.6*@button_size*@menubar_height, 0.6*@button_size*@menubar_height}}, stroke: {2, :black}),
             ],
                   translate: {2*buffer_around_button(), 2*buffer_around_button()})
        ])

      state = %{
        graph: graph,
        viewport: opts[:viewport]
      }

      {:ok, state, push: graph}
    end


    def filter_event(event, _from, state) do
      # handle all MenuBar input events at root level
      {:cont, {:menubar, event}, state}
    end


    defp buffer_around_button do
        ((1-@button_size)/2)*@menubar_height
    end
end