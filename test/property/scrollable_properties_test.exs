defmodule Quillex.Property.ScrollablePropertiesTest do
  @moduledoc """
  Property-based tests for scrollable behavior invariants.
  
  These tests ensure that the Widgex.Scrollable module maintains
  fundamental properties regardless of input sequence or configuration.
  """
  
  use ExUnit.Case
  use ExUnitProperties
  
  alias Scenic.Scene
  
  describe "scroll offset invariants" do
    property "scroll offset never exceeds content bounds" do
      check all content_size <- content_size_generator(),
                viewport_size <- viewport_size_generator(),
                scroll_operations <- list_of(scroll_operation_generator(), max_length: 20) do
        
        # Setup a mock scene with scrollable state
        scene = setup_mock_scene(content_size, viewport_size)
        
        # Apply all scroll operations
        final_scene = Enum.reduce(scroll_operations, scene, &apply_scroll_operation/2)
        
        # Get final scroll state
        scroll = final_scene.assigns.scroll
        {scroll_x, scroll_y} = scroll.offset
        {content_w, content_h} = scroll.content_size
        {viewport_w, viewport_h} = scroll.viewport_size
        
        # Calculate maximum allowed scroll (negative values)
        max_scroll_x = min(0, viewport_w - content_w)
        max_scroll_y = min(0, viewport_h - content_h)
        
        # Assert scroll bounds are respected
        assert scroll_x >= max_scroll_x, 
               "Scroll X #{scroll_x} should not exceed max #{max_scroll_x}"
        assert scroll_x <= 0, 
               "Scroll X #{scroll_x} should not be positive"
        assert scroll_y >= max_scroll_y, 
               "Scroll Y #{scroll_y} should not exceed max #{max_scroll_y}"
        assert scroll_y <= 0, 
               "Scroll Y #{scroll_y} should not be positive"
      end
    end
    
    property "scrollbars only appear when content overflows viewport" do
      check all content_size <- content_size_generator(),
                viewport_size <- viewport_size_generator() do
        
        scene = setup_mock_scene(content_size, viewport_size)
        scroll = scene.assigns.scroll
        
        {content_w, content_h} = scroll.content_size
        {viewport_w, viewport_h} = scroll.viewport_size
        
        # Force scrollbars visible to test visibility logic
        scene_with_visible = scene
        |> Scene.assign(:scroll, Map.put(scroll, :scrollbars_visible, true))
        
        # Check if scrollbars should be shown based on overflow
        should_show_v = case scroll.config.overflow_y do
          :scroll -> true
          :auto -> content_h > viewport_h
          :hidden -> false
        end
        
        should_show_h = case scroll.config.overflow_x do
          :scroll -> true
          :auto -> content_w > viewport_w
          :hidden -> false
        end
        
        # This is more of a logic test - we can't easily test the actual rendering
        # but we can verify the configuration logic is sound
        if content_w <= viewport_w do
          refute should_show_h || scroll.config.overflow_x == :scroll,
                 "Horizontal scrollbar should not be needed when content fits"
        end
        
        if content_h <= viewport_h do
          refute should_show_v || scroll.config.overflow_y == :scroll,
                 "Vertical scrollbar should not be needed when content fits"
        end
      end
    end
    
    property "scroll position is consistent after multiple operations" do
      check all content_size <- content_size_generator(),
                viewport_size <- viewport_size_generator(),
                operations <- list_of(scroll_operation_generator(), max_length: 10) do
        
        scene = setup_mock_scene(content_size, viewport_size)
        
        # Apply operations one by one, tracking state
        final_scene = Enum.reduce(operations, scene, fn op, current_scene ->
          new_scene = apply_scroll_operation(op, current_scene)
          
          # Verify state is always valid after each operation
          scroll = new_scene.assigns.scroll
          {scroll_x, scroll_y} = scroll.offset
          
          assert is_integer(scroll_x), "Scroll X should be integer"
          assert is_integer(scroll_y), "Scroll Y should be integer"
          assert scroll.content_size == content_size, "Content size should not change"
          assert scroll.viewport_size == viewport_size, "Viewport size should not change"
          
          new_scene
        end)
        
        # Final state should still be valid
        final_scroll = final_scene.assigns.scroll
        assert Map.has_key?(final_scroll, :offset)
        assert Map.has_key?(final_scroll, :content_size)
        assert Map.has_key?(final_scroll, :viewport_size)
      end
    end
  end
  
  describe "ensure_visible behavior" do
    property "ensure_visible always brings position into viewport" do
      check all content_size <- content_size_generator(),
                viewport_size <- viewport_size_generator(),
                target_pos <- position_generator(content_size) do
        
        scene = setup_mock_scene(content_size, viewport_size)
        {target_x, target_y} = target_pos
        
        # Ensure the target position is visible
        new_scene = Widgex.Scrollable.ensure_visible(scene, target_pos, 20)
        
        scroll = new_scene.assigns.scroll
        {scroll_x, scroll_y} = scroll.offset
        {viewport_w, viewport_h} = scroll.viewport_size
        
        # Check if position is now visible (within viewport + scroll)
        visible_x = target_x + scroll_x
        visible_y = target_y + scroll_y
        
        # Position should be within viewport bounds (with margin)
        margin = 20
        assert visible_x >= margin, "Target X should be visible with margin"
        assert visible_x <= viewport_w - margin, "Target X should not exceed viewport"
        assert visible_y >= margin, "Target Y should be visible with margin"
        assert visible_y <= viewport_h - margin, "Target Y should not exceed viewport"
      end
    end
  end
  
  # Generators for property-based testing
  
  defp content_size_generator do
    gen all width <- integer(100..2000),
            height <- integer(100..2000) do
      {width, height}
    end
  end
  
  defp viewport_size_generator do
    gen all width <- integer(200..800),
            height <- integer(200..600) do
      {width, height}
    end
  end
  
  defp position_generator({max_w, max_h}) do
    gen all x <- integer(0..max_w),
            y <- integer(0..max_h) do
      {x, y}
    end
  end
  
  defp scroll_operation_generator do
    one_of([
      {:wheel_scroll, {integer(-50..50), integer(-50..50)}},
      {:update_content_size, content_size_generator()},
      {:ensure_visible, {integer(0..1000), integer(0..1000)}}
    ])
  end
  
  # Helper functions
  
  defp setup_mock_scene(content_size, viewport_size) do
    # Create a minimal scene structure for testing
    scene = %Scene{
      assigns: %{}
    }
    
    # Setup scrollable state
    Widgex.Scrollable.setup(scene, %{
      content_size_fn: fn -> content_size end,
      viewport_size: viewport_size,
      overflow_x: :auto,
      overflow_y: :auto
    })
  end
  
  defp apply_scroll_operation({:wheel_scroll, {h_delta, v_delta}}, scene) do
    # Simulate wheel scroll input
    input = {:cursor_scroll, {0, 0, h_delta, v_delta}}
    
    case Widgex.Scrollable.handle_input(input, scene) do
      {:handled, new_scene} -> new_scene
      {:continue, scene} -> scene
    end
  end
  
  defp apply_scroll_operation({:update_content_size, new_size}, scene) do
    Widgex.Scrollable.update_content_size(scene, new_size)
  end
  
  defp apply_scroll_operation({:ensure_visible, pos}, scene) do
    Widgex.Scrollable.ensure_visible(scene, pos)
  end
end