defmodule Widgex.Behaviors.Scrollable do
  @moduledoc """
  A reusable scrollable behavior that can be applied to any Widgex widget.
  
  Provides:
  - Automatic scrollbar rendering when content overflows
  - Mouse wheel scrolling
  - Draggable scrollbar thumbs
  - Auto-scroll when cursor/focus moves out of viewport
  - Smooth scrolling animations
  
  ## Usage
  
  In your component:
  
      use Widgex.Behaviors.Scrollable
      
      def init(scene, args, opts) do
        scene = init_scrollable(scene, %{
          content_size: {800, 1200},  # Total content dimensions
          viewport_size: {400, 600},  # Visible area dimensions
          scroll_speed: 20,           # Pixels per scroll event
          scrollbar_width: 12,        # Width of scrollbars
          auto_hide: true,           # Hide scrollbars when not scrolling
          smooth_scroll: true        # Enable smooth scrolling animations
        })
        
        {:ok, scene}
      end
  """
  
  alias Scenic.Graph
  alias Scenic.Primitives
  alias Scenic.Math.Vector2
  import Scenic.Scene, only: [assign: 3, capture_input: 2, release_input: 2]
  
  defmacro __using__(opts) do
    quote do
      import Widgex.Behaviors.Scrollable
      
      # Override handle_input to add scrolling behavior
      # Only make overridable if the function already exists
      if function_exported?(__MODULE__, :handle_input, 3) do
        defoverridable [handle_input: 3]
        
        def handle_input(input, id, scene) do
          case Widgex.Behaviors.Scrollable.handle_scrollable_input(input, scene) do
            {:handled, new_scene} -> 
              {:noreply, new_scene}
            {:continue, scene} -> 
              super(input, id, scene)
          end
        end
      else
        def handle_input(input, id, scene) do
          case Widgex.Behaviors.Scrollable.handle_scrollable_input(input, scene) do
            {:handled, new_scene} -> 
              {:noreply, new_scene}
            {:continue, scene} -> 
              {:noreply, scene}
          end
        end
      end
      
      # Override handle_info to add timer handling
      if function_exported?(__MODULE__, :handle_info, 2) do
        defoverridable [handle_info: 2]
        
        def handle_info(msg, scene) do
          case Widgex.Behaviors.Scrollable.handle_scrollable_info(msg, scene) do
            {:handled, new_scene} ->
              {:noreply, new_scene}
            {:continue, scene} ->
              super(msg, scene)
          end
        end
      else
        def handle_info(msg, scene) do
          case Widgex.Behaviors.Scrollable.handle_scrollable_info(msg, scene) do
            {:handled, new_scene} ->
              {:noreply, new_scene}
            {:continue, scene} ->
              {:noreply, scene}
          end
        end
      end
      
      # Automatically initialize scrollable behavior
      if function_exported?(__MODULE__, :init, 3) do
        defoverridable [init: 3]
        
        def init(scene, args, opts) do
          # Call the original init first
          result = super(scene, args, opts)
          
          case result do
            {:ok, scene} ->
              # Auto-initialize scrollable behavior if needed
              scrollable_opts = unquote(opts) ++ Map.get(args, :scrollable, [])
              scene = Widgex.Behaviors.Scrollable.auto_init_scrollable(scene, scrollable_opts)
              {:ok, scene}
            other -> 
              other
          end
        end
      end
      
      # Auto-wrap graph rendering to include scrollbars
      if function_exported?(__MODULE__, :push_graph, 1) do
        defoverridable [push_graph: 1]
        
        def push_graph(scene) do
          if Map.has_key?(scene.assigns, :scrollable) do
            graph = scene.assigns.graph
            |> Widgex.Behaviors.Scrollable.render_scrollbars(scene)
            
            scene
            |> assign(:graph, graph)
            |> super()
          else
            super(scene)
          end
        end
      end
      
      if function_exported?(__MODULE__, :push_graph, 2) do
        defoverridable [push_graph: 2]
        
        def push_graph(scene, graph) do
          if Map.has_key?(scene.assigns, :scrollable) do
            enhanced_graph = graph
            |> Widgex.Behaviors.Scrollable.render_scrollbars(scene)
            
            super(scene, enhanced_graph)
          else
            super(scene, graph)
          end
        end
      end
      
      # Default scrollable state
      defp default_scrollable_state do
        %{
          scroll_offset: {0, 0},
          content_size: {0, 0},
          viewport_size: {0, 0},
          scroll_speed: 20,
          scrollbar_width: 12,
          auto_hide: true,
          smooth_scroll: true,
          scrollbars_visible: false,
          scrollbar_fade_timer: nil,
          dragging: nil,  # :vertical, :horizontal, or nil
          drag_start: nil,
          hover: nil,  # :vertical_thumb, :horizontal_thumb, or nil
          animation: nil
        }
      end
    end
  end
  
  @doc """
  Handle scrollable input events automatically.
  """
  def handle_scrollable_input(input, scene) do
    if Map.has_key?(scene.assigns, :scrollable) do
      case input do
        # Mouse wheel scrolling
        {:cursor_scroll, {_x, _y, h_scroll, v_scroll}} ->
          new_scene = handle_scroll_input({:scroll, {0, 0, h_scroll, v_scroll}}, scene)
          {:handled, new_scene}
          
        # Scrollbar interaction
        {:cursor_button, _} = button_input ->
          case handle_scrollbar_input(button_input, scene) do
            {:cont, scene} -> {:continue, scene}
            new_scene -> {:handled, new_scene}
          end
          
        {:cursor_pos, _} = pos_input ->
          case handle_scrollbar_input(pos_input, scene) do
            {:cont, scene} -> {:continue, scene}
            new_scene -> {:handled, new_scene}
          end
          
        _ ->
          {:continue, scene}
      end
    else
      {:continue, scene}
    end
  end
  
  @doc """
  Handle scrollable info messages automatically.
  """
  def handle_scrollable_info(msg, scene) do
    if Map.has_key?(scene.assigns, :scrollable) do
      case msg do
        :hide_scrollbars ->
          scrollable = scene.assigns.scrollable
          |> Map.put(:scrollbars_visible, false)
          |> Map.put(:scrollbar_fade_timer, nil)
          
          scene = assign(scene, :scrollable, scrollable)
          {:handled, scene}
          
        _ ->
          {:continue, scene}
      end
    else
      {:continue, scene}
    end
  end
  
  @doc """
  Auto-initialize scrollable behavior based on component content.
  """
  def auto_init_scrollable(scene, opts \\ []) do
    # Try to auto-detect content dimensions from the graph or scene
    {content_w, content_h} = auto_detect_content_size(scene)
    {viewport_w, viewport_h} = auto_detect_viewport_size(scene)
    
    if content_w > 0 && content_h > 0 && viewport_w > 0 && viewport_h > 0 do
      config = %{
        content_size: {content_w, content_h},
        viewport_size: {viewport_w, viewport_h},
        scroll_speed: Keyword.get(opts, :scroll_speed, 20),
        scrollbar_width: Keyword.get(opts, :scrollbar_width, 12),
        auto_hide: Keyword.get(opts, :auto_hide, true),
        smooth_scroll: Keyword.get(opts, :smooth_scroll, false)
      }
      
      init_scrollable(scene, config)
    else
      scene
    end
  end
  
  defp auto_detect_content_size(scene) do
    # Try to get content size from buffer data if it's a text editor
    cond do
      Map.has_key?(scene.assigns, :buf) ->
        buf = scene.assigns.buf
        line_count = length(buf.data)
        max_line_width = buf.data
        |> Enum.map(&String.length/1)
        |> Enum.max(fn -> 0 end)
        
        line_height = if Map.has_key?(scene.assigns, :state) && 
                         Map.has_key?(scene.assigns.state, :font) do
          scene.assigns.state.font.size
        else
          24  # Default line height
        end
        
        char_width = 12  # Approximate character width
        content_width = max_line_width * char_width + 100
        content_height = line_count * line_height
        
        {content_width, content_height}
        
      # Try to get bounds from the graph
      Map.has_key?(scene.assigns, :graph) ->
        try do
          {_left, _top, right, bottom} = Scenic.Graph.bounds(scene.assigns.graph)
          {right, bottom}
        rescue
          _ -> {0, 0}
        end
        
      true ->
        {0, 0}
    end
  end
  
  defp auto_detect_viewport_size(scene) do
    cond do
      Map.has_key?(scene.assigns, :frame) ->
        frame = scene.assigns.frame
        {frame.size.width, frame.size.height}
        
      true ->
        {400, 300}  # Default viewport size
    end
  end

  @doc """
  Initialize scrollable behavior for a scene.
  """
  def init_scrollable(scene, config \\ %{}) do
    scrollable_state = Map.merge(default_scrollable_state(), config)
    
    scene
    |> assign(:scrollable, scrollable_state)
    |> update_scrollbar_visibility()
  end
  
  defp default_scrollable_state do
    %{
      scroll_offset: {0, 0},
      content_size: {0, 0},
      viewport_size: {0, 0},
      scroll_speed: 20,
      scrollbar_width: 12,
      auto_hide: true,
      smooth_scroll: true,
      scrollbars_visible: false,
      scrollbar_fade_timer: nil,
      dragging: nil,  # :vertical, :horizontal, or nil
      drag_start: nil,
      hover: nil,  # :vertical_thumb, :horizontal_thumb, or nil
      animation: nil
    }
  end
  
  @doc """
  Update the content or viewport size and recalculate scrollbars.
  """
  def update_scroll_bounds(scene, content_size, viewport_size) do
    scrollable = scene.assigns.scrollable
    |> Map.put(:content_size, content_size)
    |> Map.put(:viewport_size, viewport_size)
    |> constrain_scroll_offset()
    
    scene
    |> assign(:scrollable, scrollable)
    |> update_scrollbar_visibility()
  end
  
  @doc """
  Handle scroll input events (mouse wheel, touch scroll, etc).
  """
  def handle_scroll_input({:scroll, {_x, _y, delta_x, delta_y}}, scene) do
    scrollable = scene.assigns.scrollable
    {scroll_x, scroll_y} = scrollable.scroll_offset
    speed = scrollable.scroll_speed
    
    # Calculate new scroll position
    new_offset = {
      scroll_x - (delta_x * speed),
      scroll_y - (delta_y * speed)
    }
    
    scrollable = scrollable
    |> Map.put(:scroll_offset, new_offset)
    |> constrain_scroll_offset()
    |> show_scrollbars_temporarily()
    
    scene
    |> assign(:scrollable, scrollable)
    |> update_scrollbar_visibility()
  end
  
  @doc """
  Handle mouse events for scrollbar interaction.
  """
  def handle_scrollbar_input({:cursor_button, {:btn_left, 1, _, pos}}, scene) do
    scrollable = scene.assigns.scrollable
    
    cond do
      hit = hit_test_scrollbar(pos, scene, :vertical) ->
        start_scrollbar_drag(scene, :vertical, pos, hit)
        
      hit = hit_test_scrollbar(pos, scene, :horizontal) ->
        start_scrollbar_drag(scene, :horizontal, pos, hit)
        
      true ->
        {:cont, scene}
    end
  end
  
  def handle_scrollbar_input({:cursor_button, {:btn_left, 0, _, _pos}}, scene) do
    case scene.assigns.scrollable.dragging do
      nil -> {:cont, scene}
      _ -> stop_scrollbar_drag(scene)
    end
  end
  
  def handle_scrollbar_input({:cursor_pos, pos}, scene) do
    scrollable = scene.assigns.scrollable
    
    case scrollable.dragging do
      nil ->
        # Update hover state
        hover = cond do
          hit_test_scrollbar(pos, scene, :vertical) -> :vertical_thumb
          hit_test_scrollbar(pos, scene, :horizontal) -> :horizontal_thumb
          true -> nil
        end
        
        if hover != scrollable.hover do
          scene
          |> assign(:scrollable, Map.put(scrollable, :hover, hover))
        else
          {:cont, scene}
        end
        
      direction ->
        # Handle dragging
        update_scrollbar_drag(scene, direction, pos)
    end
  end
  
  @doc """
  Render scrollbars on top of existing graph.
  """
  def render_scrollbars(graph, scene) do
    scrollable = scene.assigns.scrollable
    {content_w, content_h} = scrollable.content_size
    {viewport_w, viewport_h} = scrollable.viewport_size
    {scroll_x, scroll_y} = scrollable.scroll_offset
    
    needs_vertical = content_h > viewport_h
    needs_horizontal = content_w > viewport_w
    
    graph
    |> render_vertical_scrollbar(scene, needs_vertical)
    |> render_horizontal_scrollbar(scene, needs_horizontal)
  end
  
  defp render_vertical_scrollbar(graph, scene, false), do: graph
  defp render_vertical_scrollbar(graph, scene, true) do
    scrollable = scene.assigns.scrollable
    {_content_w, content_h} = scrollable.content_size
    {viewport_w, viewport_h} = scrollable.viewport_size
    {_scroll_x, scroll_y} = scrollable.scroll_offset
    bar_width = scrollable.scrollbar_width
    
    # Calculate scrollbar dimensions
    scrollable_height = content_h - viewport_h
    thumb_height = max(30, viewport_h * viewport_h / content_h)
    thumb_y = -scroll_y * (viewport_h - thumb_height) / scrollable_height
    
    # Scrollbar track
    track_color = {:color, {200, 200, 200, if(scrollable.scrollbars_visible, do: 100, else: 0)}}
    thumb_color = case scrollable do
      %{dragging: :vertical} -> {:color, {100, 100, 100, 200}}
      %{hover: :vertical_thumb} -> {:color, {120, 120, 120, 180}}
      _ -> {:color, {140, 140, 140, if(scrollable.scrollbars_visible, do: 160, else: 0)}}
    end
    
    graph
    |> Primitives.rect({bar_width, viewport_h},
      id: :scrollbar_vertical_track,
      fill: track_color,
      translate: {viewport_w - bar_width, 0}
    )
    |> Primitives.rrect({bar_width - 4, thumb_height, 3},
      id: :scrollbar_vertical_thumb,
      fill: thumb_color,
      translate: {viewport_w - bar_width + 2, thumb_y}
    )
  end
  
  defp render_horizontal_scrollbar(graph, scene, false), do: graph
  defp render_horizontal_scrollbar(graph, scene, true) do
    scrollable = scene.assigns.scrollable
    {content_w, _content_h} = scrollable.content_size
    {viewport_w, viewport_h} = scrollable.viewport_size
    {scroll_x, _scroll_y} = scrollable.scroll_offset
    bar_width = scrollable.scrollbar_width
    
    # Calculate scrollbar dimensions
    scrollable_width = content_w - viewport_w
    thumb_width = max(30, viewport_w * viewport_w / content_w)
    thumb_x = -scroll_x * (viewport_w - thumb_width) / scrollable_width
    
    # Scrollbar track
    track_color = {:color, {200, 200, 200, if(scrollable.scrollbars_visible, do: 100, else: 0)}}
    thumb_color = case scrollable do
      %{dragging: :horizontal} -> {:color, {100, 100, 100, 200}}
      %{hover: :horizontal_thumb} -> {:color, {120, 120, 120, 180}}
      _ -> {:color, {140, 140, 140, if(scrollable.scrollbars_visible, do: 160, else: 0)}}
    end
    
    graph
    |> Primitives.rect({viewport_w, bar_width},
      id: :scrollbar_horizontal_track,
      fill: track_color,
      translate: {0, viewport_h - bar_width}
    )
    |> Primitives.rrect({thumb_width, bar_width - 4, 3},
      id: :scrollbar_horizontal_thumb,
      fill: thumb_color,
      translate: {thumb_x, viewport_h - bar_width + 2}
    )
  end
  
  @doc """
  Auto-scroll to ensure a given position is visible in the viewport.
  """
  def ensure_visible(scene, {x, y}, opts \\ []) do
    scrollable = scene.assigns.scrollable
    {viewport_w, viewport_h} = scrollable.viewport_size
    {scroll_x, scroll_y} = scrollable.scroll_offset
    
    margin = Keyword.get(opts, :margin, 20)
    animate = Keyword.get(opts, :animate, scrollable.smooth_scroll)
    
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
      scrollable = scrollable
      |> Map.put(:scroll_offset, {new_scroll_x, new_scroll_y})
      |> constrain_scroll_offset()
      |> show_scrollbars_temporarily()
      
      scene
      |> assign(:scrollable, scrollable)
      |> update_scrollbar_visibility()
    else
      scene
    end
  end
  
  # Private helper functions
  
  defp constrain_scroll_offset(scrollable) do
    {content_w, content_h} = scrollable.content_size
    {viewport_w, viewport_h} = scrollable.viewport_size
    {scroll_x, scroll_y} = scrollable.scroll_offset
    
    max_scroll_x = min(0, viewport_w - content_w)
    max_scroll_y = min(0, viewport_h - content_h)
    
    new_offset = {
      max(max_scroll_x, min(0, scroll_x)),
      max(max_scroll_y, min(0, scroll_y))
    }
    
    Map.put(scrollable, :scroll_offset, new_offset)
  end
  
  defp show_scrollbars_temporarily(scrollable) do
    # Cancel existing fade timer
    if scrollable.scrollbar_fade_timer do
      Process.cancel_timer(scrollable.scrollbar_fade_timer)
    end
    
    # Set new fade timer if auto-hide is enabled
    timer = if scrollable.auto_hide do
      Process.send_after(self(), :hide_scrollbars, 1500)
    else
      nil
    end
    
    scrollable
    |> Map.put(:scrollbars_visible, true)
    |> Map.put(:scrollbar_fade_timer, timer)
  end
  
  defp update_scrollbar_visibility(scene) do
    scrollable = scene.assigns.scrollable
    {content_w, content_h} = scrollable.content_size
    {viewport_w, viewport_h} = scrollable.viewport_size
    
    needs_scrollbars = content_w > viewport_w || content_h > viewport_h
    
    if needs_scrollbars && !scrollable.auto_hide && !scrollable.scrollbars_visible do
      scene
      |> assign(:scrollable, Map.put(scrollable, :scrollbars_visible, true))
    else
      scene
    end
  end
  
  defp hit_test_scrollbar({x, y}, scene, :vertical) do
    scrollable = scene.assigns.scrollable
    {_content_w, content_h} = scrollable.content_size
    {viewport_w, viewport_h} = scrollable.viewport_size
    bar_width = scrollable.scrollbar_width
    
    if content_h > viewport_h && x >= viewport_w - bar_width && x <= viewport_w && y >= 0 && y <= viewport_h do
      # Check if hit is on thumb
      {_scroll_x, scroll_y} = scrollable.scroll_offset
      scrollable_height = content_h - viewport_h
      thumb_height = max(30, viewport_h * viewport_h / content_h)
      thumb_y = -scroll_y * (viewport_h - thumb_height) / scrollable_height
      
      if y >= thumb_y && y <= thumb_y + thumb_height do
        {:thumb, y - thumb_y}
      else
        {:track, y}
      end
    else
      nil
    end
  end
  
  defp hit_test_scrollbar({x, y}, scene, :horizontal) do
    scrollable = scene.assigns.scrollable
    {content_w, _content_h} = scrollable.content_size
    {viewport_w, viewport_h} = scrollable.viewport_size
    bar_width = scrollable.scrollbar_width
    
    if content_w > viewport_w && y >= viewport_h - bar_width && y <= viewport_h && x >= 0 && x <= viewport_w do
      # Check if hit is on thumb
      {scroll_x, _scroll_y} = scrollable.scroll_offset
      scrollable_width = content_w - viewport_w
      thumb_width = max(30, viewport_w * viewport_w / content_w)
      thumb_x = -scroll_x * (viewport_w - thumb_width) / scrollable_width
      
      if x >= thumb_x && x <= thumb_x + thumb_width do
        {:thumb, x - thumb_x}
      else
        {:track, x}
      end
    else
      nil
    end
  end
  
  defp start_scrollbar_drag(scene, direction, pos, {:thumb, offset}) do
    scrollable = scene.assigns.scrollable
    |> Map.put(:dragging, direction)
    |> Map.put(:drag_start, {pos, offset})
    
    scene
    |> assign(:scrollable, scrollable)
    |> capture_input([:cursor_button, :cursor_pos])
  end
  
  defp start_scrollbar_drag(scene, direction, {x, y}, {:track, _}) do
    # Clicked on track - jump to position
    scrollable = scene.assigns.scrollable
    {content_w, content_h} = scrollable.content_size
    {viewport_w, viewport_h} = scrollable.viewport_size
    
    new_offset = case direction do
      :vertical ->
        scrollable_height = content_h - viewport_h
        thumb_height = max(30, viewport_h * viewport_h / content_h)
        scroll_y = -(y - thumb_height/2) * scrollable_height / (viewport_h - thumb_height)
        {elem(scrollable.scroll_offset, 0), scroll_y}
        
      :horizontal ->
        scrollable_width = content_w - viewport_w
        thumb_width = max(30, viewport_w * viewport_w / content_w)
        scroll_x = -(x - thumb_width/2) * scrollable_width / (viewport_w - thumb_width)
        {scroll_x, elem(scrollable.scroll_offset, 1)}
    end
    
    scrollable = scrollable
    |> Map.put(:scroll_offset, new_offset)
    |> constrain_scroll_offset()
    
    scene
    |> assign(:scrollable, scrollable)
  end
  
  defp update_scrollbar_drag(scene, :vertical, {_x, y}) do
    scrollable = scene.assigns.scrollable
    {{_start_x, start_y}, offset} = scrollable.drag_start
    {content_w, content_h} = scrollable.content_size
    {viewport_w, viewport_h} = scrollable.viewport_size
    
    delta_y = y - start_y
    scrollable_height = content_h - viewport_h
    thumb_height = max(30, viewport_h * viewport_h / content_h)
    
    new_scroll_y = -(delta_y * scrollable_height / (viewport_h - thumb_height))
    
    scrollable = scrollable
    |> Map.put(:scroll_offset, {elem(scrollable.scroll_offset, 0), new_scroll_y})
    |> constrain_scroll_offset()
    
    scene
    |> assign(:scrollable, scrollable)
  end
  
  defp update_scrollbar_drag(scene, :horizontal, {x, _y}) do
    scrollable = scene.assigns.scrollable
    {{start_x, _start_y}, offset} = scrollable.drag_start
    {content_w, content_h} = scrollable.content_size
    {viewport_w, viewport_h} = scrollable.viewport_size
    
    delta_x = x - start_x
    scrollable_width = content_w - viewport_w
    thumb_width = max(30, viewport_w * viewport_w / content_w)
    
    new_scroll_x = -(delta_x * scrollable_width / (viewport_w - thumb_width))
    
    scrollable = scrollable
    |> Map.put(:scroll_offset, {new_scroll_x, elem(scrollable.scroll_offset, 1)})
    |> constrain_scroll_offset()
    
    scene
    |> assign(:scrollable, scrollable)
  end
  
  defp stop_scrollbar_drag(scene) do
    scrollable = scene.assigns.scrollable
    |> Map.put(:dragging, nil)
    |> Map.put(:drag_start, nil)
    
    scene
    |> assign(:scrollable, scrollable)
    |> release_input([:cursor_button, :cursor_pos])
  end
end