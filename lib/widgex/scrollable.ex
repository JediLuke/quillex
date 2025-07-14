defmodule Widgex.Scrollable do
  @moduledoc """
  Simple scrollable helper for components that need internal scrolling.
  
  Provides:
  - Scroll state management
  - Mouse wheel input handling  
  - VS Code-style scrollbar rendering
  - Proper bounds checking
  - Translation-based content scrolling
  
  ## Usage
  
  In your component:
  
      def init(scene, args, opts) do
        scene = scene
        |> Widgex.Scrollable.setup(%{
          content_size_fn: fn -> calculate_content_size(scene.assigns) end,
          viewport_size: {800, 600},
          overflow_x: :auto,
          overflow_y: :scroll
        })
        
        {:ok, scene}
      end
      
      def handle_input(input, _id, scene) do
        case Widgex.Scrollable.handle_input(input, scene) do
          {:handled, new_scene} -> 
            # Re-render with scroll applied
            graph = render_content(new_scene.assigns)
            |> Widgex.Scrollable.apply_scroll(new_scene)
            {:noreply, push_graph(new_scene, graph)}
          {:continue, scene} ->
            # Handle your component's input
            handle_component_input(input, scene)
        end
      end
  """
  
  alias Scenic.Graph
  alias Scenic.Primitives
  alias Scenic.Math.Vector2
  import Scenic.Scene, only: [assign: 3]
  
  @type scroll_config :: %{
    content_size_fn: (-> {integer(), integer()}),
    viewport_size: {integer(), integer()},
    overflow_x: :auto | :scroll | :hidden,
    overflow_y: :auto | :scroll | :hidden,
    scroll_speed: integer(),
    scrollbar_width: integer(),
    auto_hide: boolean(),
    fade_timeout: integer()
  }
  
  @type scroll_state :: %{
    offset: {integer(), integer()},
    content_size: {integer(), integer()},
    viewport_size: {integer(), integer()},
    config: scroll_config(),
    scrollbars_visible: boolean(),
    fade_timer: reference() | nil,
    dragging: nil | :vertical | :horizontal,
    drag_start: {integer(), integer()} | nil,
    hover: nil | :v_thumb | :h_thumb | :v_track | :h_track
  }
  
  @default_config %{
    overflow_x: :auto,
    overflow_y: :auto,
    scroll_speed: 20,
    scrollbar_width: 12,
    auto_hide: true,
    fade_timeout: 1500
  }
  
  @doc """
  Initialize scrollable state for a scene.
  """
  @spec setup(Scenic.Scene.t(), scroll_config()) :: Scenic.Scene.t()
  def setup(scene, config) do
    full_config = Map.merge(@default_config, config)
    
    # Get initial content size
    {content_w, content_h} = if full_config.content_size_fn do
      full_config.content_size_fn.()
    else
      {0, 0}
    end
    
    scroll_state = %{
      offset: {0, 0},
      content_size: {content_w, content_h},
      viewport_size: full_config.viewport_size,
      config: full_config,
      scrollbars_visible: false,
      fade_timer: nil,
      dragging: nil,
      drag_start: nil,
      hover: nil
    }
    
    assign(scene, :scroll, scroll_state)
  end
  
  @doc """
  Handle input events for scrolling. Returns {:handled, scene} or {:continue, scene}.
  """
  @spec handle_input(any(), Scenic.Scene.t()) :: {:handled | :continue, Scenic.Scene.t()}
  def handle_input(input, scene) do
    if Map.has_key?(scene.assigns, :scroll) do
      case input do
        {:cursor_scroll, {_x, _y, h_scroll, v_scroll}} ->
          new_scene = handle_wheel_scroll(scene, {h_scroll, v_scroll})
          {:handled, new_scene}
          
        {:cursor_button, {:btn_left, 1, _, pos}} ->
          case handle_mouse_down(scene, pos) do
            {:handled, new_scene} -> {:handled, new_scene}
            :continue -> {:continue, scene}
          end
          
        {:cursor_button, {:btn_left, 0, _, _pos}} ->
          case handle_mouse_up(scene) do
            {:handled, new_scene} -> {:handled, new_scene}
            :continue -> {:continue, scene}
          end
          
        {:cursor_pos, pos} ->
          case handle_mouse_move(scene, pos) do
            {:handled, new_scene} -> {:handled, new_scene}
            :continue -> {:continue, scene}
          end
          
        _ ->
          {:continue, scene}
      end
    else
      {:continue, scene}
    end
  end
  
  @doc """
  Apply scroll transform and render scrollbars on a graph.
  """
  @spec apply_scroll(Graph.t(), Scenic.Scene.t()) :: Graph.t()
  def apply_scroll(graph, scene) do
    if Map.has_key?(scene.assigns, :scroll) do
      scroll = scene.assigns.scroll
      {scroll_x, scroll_y} = scroll.offset
      
      graph
      |> Graph.modify(:scrollable_content, fn primitive ->
        Primitives.update_opts(primitive, translate: {scroll_x, scroll_y})
      end)
      |> render_scrollbars(scroll)
    else
      graph
    end
  end
  
  
  @doc """
  Update content size and refresh scroll state.
  """
  @spec update_content_size(Scenic.Scene.t(), {integer(), integer()}) :: Scenic.Scene.t()
  def update_content_size(scene, new_size) do
    if Map.has_key?(scene.assigns, :scroll) do
      scroll = scene.assigns.scroll
      |> Map.put(:content_size, new_size)
      |> constrain_scroll_offset()
      |> update_scrollbar_visibility()
      
      assign(scene, :scroll, scroll)
    else
      scene
    end
  end
  
  @doc """
  Ensure a position is visible by auto-scrolling if needed.
  """
  @spec ensure_visible(Scenic.Scene.t(), {integer(), integer()}, integer()) :: Scenic.Scene.t()
  def ensure_visible(scene, {x, y}, margin \\ 20) do
    if Map.has_key?(scene.assigns, :scroll) do
      scroll = scene.assigns.scroll
      {viewport_w, viewport_h} = scroll.viewport_size
      {scroll_x, scroll_y} = scroll.offset
      
      # Calculate required scroll adjustment
      new_scroll_x = cond do
        x + scroll_x < margin -> -(x - margin)
        x + scroll_x > viewport_w - margin -> -(x - viewport_w + margin)
        true -> scroll_x
      end
      
      new_scroll_y = cond do
        y + scroll_y < margin -> -(y - margin)
        y + scroll_y > viewport_h - margin -> -(y - viewport_h + margin)
        true -> scroll_y
      end
      
      if {new_scroll_x, new_scroll_y} != {scroll_x, scroll_y} do
        new_scroll = scroll
        |> Map.put(:offset, {new_scroll_x, new_scroll_y})
        |> constrain_scroll_offset()
        |> show_scrollbars_temporarily()
        
        assign(scene, :scroll, new_scroll)
      else
        scene
      end
    else
      scene
    end
  end
  
  # Private functions
  
  defp handle_wheel_scroll(scene, {h_delta, v_delta}) do
    scroll = scene.assigns.scroll
    {scroll_x, scroll_y} = scroll.offset
    speed = scroll.config.scroll_speed
    
    new_offset = {
      scroll_x - (h_delta * speed),
      scroll_y - (v_delta * speed)
    }
    
    new_scroll = scroll
    |> Map.put(:offset, new_offset)
    |> constrain_scroll_offset()
    |> show_scrollbars_temporarily()
    
    assign(scene, :scroll, new_scroll)
  end
  
  defp handle_mouse_down(scene, {x, y}) do
    scroll = scene.assigns.scroll
    
    cond do
      hit = hit_test_scrollbar({x, y}, scroll, :vertical) ->
        new_scroll = start_drag(scroll, :vertical, {x, y}, hit)
        {:handled, assign(scene, :scroll, new_scroll)}
        
      hit = hit_test_scrollbar({x, y}, scroll, :horizontal) ->
        new_scroll = start_drag(scroll, :horizontal, {x, y}, hit)
        {:handled, assign(scene, :scroll, new_scroll)}
        
      true ->
        :continue
    end
  end
  
  defp handle_mouse_up(scene) do
    scroll = scene.assigns.scroll
    
    if scroll.dragging do
      new_scroll = scroll
      |> Map.put(:dragging, nil)
      |> Map.put(:drag_start, nil)
      
      {:handled, assign(scene, :scroll, new_scroll)}
    else
      :continue
    end
  end
  
  defp handle_mouse_move(scene, {x, y}) do
    scroll = scene.assigns.scroll
    
    case scroll.dragging do
      nil ->
        # Update hover state
        new_hover = cond do
          hit_test_scrollbar({x, y}, scroll, :vertical) -> :v_thumb
          hit_test_scrollbar({x, y}, scroll, :horizontal) -> :h_thumb
          true -> nil
        end
        
        if new_hover != scroll.hover do
          new_scroll = Map.put(scroll, :hover, new_hover)
          {:handled, assign(scene, :scroll, new_scroll)}
        else
          :continue
        end
        
      direction ->
        # Handle drag
        new_scroll = update_drag(scroll, direction, {x, y})
        {:handled, assign(scene, :scroll, new_scroll)}
    end
  end
  
  defp constrain_scroll_offset(scroll) do
    {content_w, content_h} = scroll.content_size
    {viewport_w, viewport_h} = scroll.viewport_size
    {scroll_x, scroll_y} = scroll.offset
    
    # Calculate maximum scroll (negative values)
    max_scroll_x = min(0, viewport_w - content_w)
    max_scroll_y = min(0, viewport_h - content_h)
    
    # Constrain scroll offset
    new_offset = {
      max(max_scroll_x, min(0, scroll_x)),
      max(max_scroll_y, min(0, scroll_y))
    }
    
    Map.put(scroll, :offset, new_offset)
  end
  
  defp show_scrollbars_temporarily(scroll) do
    # Cancel existing timer
    if scroll.fade_timer do
      Process.cancel_timer(scroll.fade_timer)
    end
    
    # Set new timer if auto-hide enabled
    timer = if scroll.config.auto_hide do
      Process.send_after(self(), :hide_scrollbars, scroll.config.fade_timeout)
    else
      nil
    end
    
    scroll
    |> Map.put(:scrollbars_visible, true)
    |> Map.put(:fade_timer, timer)
  end
  
  defp update_scrollbar_visibility(scroll) do
    {content_w, content_h} = scroll.content_size
    {viewport_w, viewport_h} = scroll.viewport_size
    
    needs_scrollbars = content_w > viewport_w || content_h > viewport_h
    
    if needs_scrollbars && !scroll.config.auto_hide do
      Map.put(scroll, :scrollbars_visible, true)
    else
      scroll
    end
  end
  
  defp render_scrollbars(graph, scroll) do
    {content_w, content_h} = scroll.content_size
    {viewport_w, viewport_h} = scroll.viewport_size
    
    needs_v_scroll = should_show_scrollbar(scroll, :vertical)
    needs_h_scroll = should_show_scrollbar(scroll, :horizontal)
    
    graph
    |> render_vertical_scrollbar(scroll, needs_v_scroll)
    |> render_horizontal_scrollbar(scroll, needs_h_scroll)
  end
  
  defp should_show_scrollbar(scroll, :vertical) do
    {_content_w, content_h} = scroll.content_size
    {_viewport_w, viewport_h} = scroll.viewport_size
    
    case scroll.config.overflow_y do
      :scroll -> true
      :auto -> content_h > viewport_h && scroll.scrollbars_visible
      :hidden -> false
    end
  end
  
  defp should_show_scrollbar(scroll, :horizontal) do
    {content_w, _content_h} = scroll.content_size
    {viewport_w, _viewport_h} = scroll.viewport_size
    
    case scroll.config.overflow_x do
      :scroll -> true
      :auto -> content_w > viewport_w && scroll.scrollbars_visible
      :hidden -> false
    end
  end
  
  defp render_vertical_scrollbar(graph, _scroll, false), do: graph
  defp render_vertical_scrollbar(graph, scroll, true) do
    {_content_w, content_h} = scroll.content_size
    {viewport_w, viewport_h} = scroll.viewport_size
    {_scroll_x, scroll_y} = scroll.offset
    bar_width = scroll.config.scrollbar_width
    
    # Calculate scrollbar dimensions
    scrollable_height = content_h - viewport_h
    thumb_height = max(30, viewport_h * viewport_h / content_h)
    thumb_y = if scrollable_height > 0 do
      -scroll_y * (viewport_h - thumb_height) / scrollable_height
    else
      0
    end
    
    # VS Code style colors
    track_alpha = if scroll.scrollbars_visible, do: 40, else: 0
    thumb_alpha = case {scroll.dragging, scroll.hover} do
      {:vertical, _} -> 180
      {_, :v_thumb} -> 120
      _ -> if scroll.scrollbars_visible, do: 100, else: 0
    end
    
    graph
    |> Primitives.rect({bar_width, viewport_h},
      id: :scrollbar_v_track,
      fill: {:color, {80, 80, 80, track_alpha}},
      translate: {viewport_w - bar_width, 0}
    )
    |> Primitives.rrect({bar_width - 4, thumb_height, 3},
      id: :scrollbar_v_thumb,
      fill: {:color, {160, 160, 160, thumb_alpha}},
      translate: {viewport_w - bar_width + 2, thumb_y}
    )
  end
  
  defp render_horizontal_scrollbar(graph, _scroll, false), do: graph
  defp render_horizontal_scrollbar(graph, scroll, true) do
    {content_w, _content_h} = scroll.content_size
    {viewport_w, viewport_h} = scroll.viewport_size
    {scroll_x, _scroll_y} = scroll.offset
    bar_width = scroll.config.scrollbar_width
    
    # Calculate scrollbar dimensions
    scrollable_width = content_w - viewport_w
    thumb_width = max(30, viewport_w * viewport_w / content_w)
    thumb_x = if scrollable_width > 0 do
      -scroll_x * (viewport_w - thumb_width) / scrollable_width
    else
      0
    end
    
    # VS Code style colors
    track_alpha = if scroll.scrollbars_visible, do: 40, else: 0
    thumb_alpha = case {scroll.dragging, scroll.hover} do
      {:horizontal, _} -> 180
      {_, :h_thumb} -> 120
      _ -> if scroll.scrollbars_visible, do: 100, else: 0
    end
    
    graph
    |> Primitives.rect({viewport_w, bar_width},
      id: :scrollbar_h_track,
      fill: {:color, {80, 80, 80, track_alpha}},
      translate: {0, viewport_h - bar_width}
    )
    |> Primitives.rrect({thumb_width, bar_width - 4, 3},
      id: :scrollbar_h_thumb,
      fill: {:color, {160, 160, 160, thumb_alpha}},
      translate: {thumb_x, viewport_h - bar_width + 2}
    )
  end
  
  defp hit_test_scrollbar({x, y}, scroll, :vertical) do
    {_content_w, content_h} = scroll.content_size
    {viewport_w, viewport_h} = scroll.viewport_size
    bar_width = scroll.config.scrollbar_width
    
    if content_h > viewport_h && 
       x >= viewport_w - bar_width && x <= viewport_w && 
       y >= 0 && y <= viewport_h do
      :hit
    else
      nil
    end
  end
  
  defp hit_test_scrollbar({x, y}, scroll, :horizontal) do
    {content_w, _content_h} = scroll.content_size
    {viewport_w, viewport_h} = scroll.viewport_size
    bar_width = scroll.config.scrollbar_width
    
    if content_w > viewport_w && 
       y >= viewport_h - bar_width && y <= viewport_h && 
       x >= 0 && x <= viewport_w do
      :hit
    else
      nil
    end
  end
  
  defp start_drag(scroll, direction, pos, _hit) do
    scroll
    |> Map.put(:dragging, direction)
    |> Map.put(:drag_start, pos)
  end
  
  defp update_drag(scroll, direction, {x, y}) do
    {start_x, start_y} = scroll.drag_start
    
    case direction do
      :vertical ->
        {content_w, content_h} = scroll.content_size
        {viewport_w, viewport_h} = scroll.viewport_size
        
        delta_y = y - start_y
        scrollable_height = content_h - viewport_h
        thumb_height = max(30, viewport_h * viewport_h / content_h)
        
        if scrollable_height > 0 do
          scroll_delta = -delta_y * scrollable_height / (viewport_h - thumb_height)
          {scroll_x, _scroll_y} = scroll.offset
          new_offset = {scroll_x, scroll_delta}
          
          scroll
          |> Map.put(:offset, new_offset)
          |> Map.put(:drag_start, {x, y})
          |> constrain_scroll_offset()
        else
          scroll
        end
        
      :horizontal ->
        {content_w, content_h} = scroll.content_size
        {viewport_w, viewport_h} = scroll.viewport_size
        
        delta_x = x - start_x
        scrollable_width = content_w - viewport_w
        thumb_width = max(30, viewport_w * viewport_w / content_w)
        
        if scrollable_width > 0 do
          scroll_delta = -delta_x * scrollable_width / (viewport_w - thumb_width)
          {_scroll_x, scroll_y} = scroll.offset
          new_offset = {scroll_delta, scroll_y}
          
          scroll
          |> Map.put(:offset, new_offset)
          |> Map.put(:drag_start, {x, y})
          |> constrain_scroll_offset()
        else
          scroll
        end
    end
  end
end