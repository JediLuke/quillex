defmodule Quillex.GUI.ProjectPathHeader do
  @moduledoc """
  Inert project-root label above the file navigator.

  Long paths begin right-aligned on their basename end. The wheel moves the
  path horizontally without affecting the tree beneath it.
  """
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  import Scenic.Primitives

  @padding 8

  @impl Scenic.Component
  def validate(%{frame: %{pin: _, size: _}, path: path} = data) when is_binary(path),
    do: {:ok, data}

  def validate(data),
    do: {:error, "ProjectPathHeader requires :frame and :path, got #{inspect(data)}"}

  @impl Scenic.Scene
  def init(scene, data, _opts) do
    assigns = header_assigns(data)
    graph = render(assigns)
    {:ok, scene |> assign(assigns) |> assign(graph: graph) |> push_graph(graph)}
  end

  @impl Scenic.Scene
  def handle_input({:cursor_scroll, {{dx, dy}, _coords}}, :project_path_hit, scene),
    do: scroll(scene, if(dx == 0, do: dy, else: dx))

  def handle_input({:cursor_scroll, {dx, dy, _x, _y}}, :project_path_hit, scene),
    do: scroll(scene, if(dx == 0, do: dy, else: dx))

  def handle_input(_input, _context, scene), do: {:noreply, scene}

  @impl Scenic.Scene
  def handle_put({:update, data}, scene) do
    old = scene.assigns
    next = header_assigns(data)

    # Keep the person's place while merely resizing; a new project path opens
    # at its useful right-hand end.
    offset =
      if old.path == next.path,
        do: min(old.offset, next.max_offset),
        else: next.max_offset

    redraw(scene, Map.put(next, :offset, offset))
  end

  defp header_assigns(data) do
    font_size = get_in(data, [:theme, :font_size]) || 12
    width = data.frame.size.width
    text_width = String.length(data.path) * font_size * 0.61
    max_offset = max(text_width - max(width - @padding * 2, 1), 0)

    %{
      frame: data.frame,
      path: data.path,
      theme: data.theme,
      max_offset: max_offset,
      offset: max_offset
    }
  end

  defp scroll(scene, delta) do
    next = scene.assigns.offset - delta * 28
    redraw(scene, %{scene.assigns | offset: next |> max(0) |> min(scene.assigns.max_offset)})
  end

  defp redraw(scene, assigns) do
    graph = render(assigns)
    {:noreply, scene |> assign(assigns) |> assign(graph: graph) |> push_graph(graph)}
  end

  defp render(assigns) do
    %{size: %{width: width, height: height}} = assigns.frame
    theme = assigns.theme
    font_size = theme.font_size

    Graph.build()
    |> rect({width, height},
      id: :project_path_hit,
      fill: theme.background,
      input: [:cursor_scroll]
    )
    |> group(
      fn graph ->
        text(graph, assigns.path,
          id: :project_path_text,
          fill: theme.dim_text,
          font: theme.font,
          font_size: font_size,
          text_align: :left,
          translate: {-assigns.offset, height / 2 + font_size / 3}
        )
      end,
      id: :project_path_clip,
      scissor: {width - @padding * 2, height},
      translate: {@padding, 0}
    )
    |> line({{0, height - 1}, {width, height - 1}}, stroke: {1, theme.border})
  end
end
