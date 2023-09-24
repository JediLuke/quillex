defmodule QuillEx.GUI.Components.PlainTextScrollable do
  use Widgex.Component

  defstruct widgex: nil,
            text: ""

  def draw(text) when is_binary(text) do
    %__MODULE__{
      widgex: %Widgex.Component.Widget{
        id: :plaintext,
        # frame: %Frame{},
        theme: QuillEx.GUI.Themes.midnight_shadow()
      },
      text: text
    }
  end

  def render(%Scenic.Graph{} = graph, %__MODULE__{} = state, %Frame{} = f) do
    graph |> fill_frame(f, color: state.widgex.theme.background)
  end
end

# defmodule QuillEx.GUI.Components.PlainTextScrollable do
#   # this module renders text inside a frame, but it *can* be scrolled, though it0er] has no rich-text or "smart" display, e.g. it can't handle tabs
#   use Scenic.Component
#   alias Widgex.Structs.{Coordinates, Dimensions, Frame}

#   # Define the struct for PlainText
#   # We could have 2 structs, one which is the state, and one which is the component
#   # instead of defstruct macro, use like defwidget or defcomponent
#   defstruct id: nil,
#             text: nil,
#             theme: nil,
#             scroll: {0, 0},
#             file_bar: %{
#               show?: true,
#               filename: nil
#             }

#   # Validate function to ensure proper parameters are being passed.
#   def validate({%__MODULE__{text: text} = state, %Frame{} = frame})
#       when is_binary(text) do
#     {:ok, {state, frame}}
#   end

#   def new(%{text: t}) when is_binary(t) do
#     raise "woopsey"
#     %__MODULE__{text: t}
#   end

#   def draw(text) when is_binary(text) do
#     %__MODULE__{
#       id: :plaintext,
#       text: text,
#       theme: QuillEx.GUI.Themes.midnight_shadow()
#     }
#   end

#   def init(scene, {%__MODULE__{} = state, %Frame{} = frame}, _opts) do
#     init_graph = render(state, frame)
#     init_scene = scene |> assign(graph: init_graph) |> push_graph(init_graph)

#     # request_input(init_scene, [:cursor_scroll])

#     {:ok, init_scene}
#   end

#   # def handle_info(:redraw, scene) do
#   #   new_graph = render(%{text: scene.assigns.text, frame: scene.assigns.frame})

#   #   new_scene = scene |> assign(graph: new_graph) |> push_graph(new_graph)
#   #   {:noreply, new_scene}
#   # end

#   # This is the left-hand margin, text-editors just look better with a bit of left margin
#   @left_margin 5

#   # Scenic uses this text size by default, we need to use it to apply translations
#   @default_text_size 24

#   # TODO apply scissor
#   def render(%__MODULE__{text: text} = state, %Frame{} = frame) when is_binary(text) do
#     text_box_sub_frame = Dimensions.box(frame.size)

#     Scenic.Graph.build(font: :ibm_plex_mono)
#     |> Scenic.Primitives.group(
#       fn graph ->
#         graph
#         |> render_background(state, frame)
#         |> Scenic.Primitives.text(text,
#           translate: {@left_margin, @default_text_size},
#           fill: state.theme.text
#         )
#       end,
#       id: __MODULE__,
#       scissor: Dimensions.box(frame.size),
#       translate: Coordinates.point(frame.pin)
#     )
#   end

#   def render_background(
#         %Scenic.Graph{} = graph,
#         %__MODULE__{} = state,
#         %Frame{size: f_size}
#       ) do
#     graph
#     |> Scenic.Primitives.rect(Dimensions.box(f_size),
#       # fill: state.theme.background,
#       # fill: :red,
#       opacity: 0.5,
#       input: :cursor_scroll
#     )
#   end

#   # def render_background(
#   #       %Scenic.Graph{} = graph,
#   #       _state,
#   #       %Frame{size: f_size}
#   #     ) do
#   #   graph
#   #   |> Scenic.Primitives.rect(Dimensions.box(f_size),
#   #     opacity: 0.5,
#   #     input: :cursor_scroll
#   #   )
#   # end

#   def handle_input(
#         {:cursor_scroll, {{_x_scroll, y_scroll} = delta_scroll, coords}},
#         _context,
#         scene
#       ) do
#     # Logger.debug("SCROLLING: #{inspect(delta_scroll)}")
#     # IO.puts("YES YES YES #{inspect(delta_scroll)}")
#     {:noreply, scene}
#   end
# end
