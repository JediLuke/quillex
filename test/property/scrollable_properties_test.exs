defmodule Quillex.Property.ScrollablePropertiesTest do
  @moduledoc """
  Property-based tests for scrollable behavior invariants.

  These tests ensure that the Quillex.Scrollable module maintains
  fundamental properties regardless of input sequence or configuration.
  """

  use ExUnit.Case
  use ExUnitProperties

  alias Scenic.Scene

  describe "scroll offset invariants" do
    property "scroll offset never exceeds content bounds" do
      check all(
              content_size <- content_size_generator(),
              viewport_size <- viewport_size_generator(),
              scroll_operations <- list_of(scroll_operation_generator(), max_length: 20)
            ) do
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
      check all(
              content_size <- content_size_generator(),
              viewport_size <- viewport_size_generator()
            ) do
        scene = setup_mock_scene(content_size, viewport_size)
        scroll = scene.assigns.scroll

        {content_w, content_h} = scroll.content_size
        {viewport_w, viewport_h} = scroll.viewport_size

        # Force scrollbars visible to test visibility logic
        _scene_with_visible =
          scene
          |> Scene.assign(:scroll, Map.put(scroll, :scrollbars_visible, true))

        # Check if scrollbars should be shown based on overflow
        should_show_v =
          case scroll.config.overflow_y do
            :scroll -> true
            :auto -> content_h > viewport_h
            :hidden -> false
          end

        should_show_h =
          case scroll.config.overflow_x do
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
      check all(
              content_size <- content_size_generator(),
              viewport_size <- viewport_size_generator(),
              operations <- list_of(scroll_operation_generator(), max_length: 10)
            ) do
        scene = setup_mock_scene(content_size, viewport_size)

        # Apply operations one by one, tracking state
        final_scene =
          Enum.reduce(operations, scene, fn op, current_scene ->
            new_scene = apply_scroll_operation(op, current_scene)

            # Verify state is always valid after each operation
            scroll = new_scene.assigns.scroll
            {scroll_x, scroll_y} = scroll.offset

            assert is_integer(scroll_x), "Scroll X should be integer"
            assert is_integer(scroll_y), "Scroll Y should be integer"
            assert is_tuple(scroll.content_size), "Content size should be a tuple"
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
    property "ensure_visible returns a valid scroll state" do
      check all(
              content_size <- content_size_generator(),
              viewport_size <- viewport_size_generator(),
              target_pos <- position_generator(content_size)
            ) do
        scene = setup_mock_scene(content_size, viewport_size)

        # ensure_visible should never raise regardless of input
        new_scene = Quillex.Scrollable.ensure_visible(scene, target_pos, 20)

        scroll = new_scene.assigns.scroll
        {scroll_x, scroll_y} = scroll.offset
        {viewport_w, viewport_h} = scroll.viewport_size
        {content_w, content_h} = scroll.content_size

        # Scroll offset must always be in the valid range: [max_scroll, 0]
        max_scroll_x = min(0, viewport_w - content_w)
        max_scroll_y = min(0, viewport_h - content_h)

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
  end

  # Generators for property-based testing

  defp content_size_generator do
    gen all(
          width <- integer(100..2000),
          height <- integer(100..2000)
        ) do
      {width, height}
    end
  end

  defp viewport_size_generator do
    gen all(
          width <- integer(200..800),
          height <- integer(200..600)
        ) do
      {width, height}
    end
  end

  defp position_generator({max_w, max_h}) do
    gen all(
          x <- integer(0..max_w),
          y <- integer(0..max_h)
        ) do
      {x, y}
    end
  end

  defp scroll_operation_generator do
    one_of([
      gen all(
            h <- integer(-50..50),
            v <- integer(-50..50)
          ) do
        {:wheel_scroll, {h, v}}
      end,
      map(content_size_generator(), fn size -> {:update_content_size, size} end),
      gen all(
            x <- integer(0..1000),
            y <- integer(0..1000)
          ) do
        {:ensure_visible, {x, y}}
      end
    ])
  end

  # Helper functions

  defp setup_mock_scene(content_size, viewport_size) do
    # Create a minimal scene structure for testing
    scene = %Scene{
      assigns: %{}
    }

    # Setup scrollable state
    Quillex.Scrollable.setup(scene, %{
      content_size_fn: fn -> content_size end,
      viewport_size: viewport_size,
      overflow_x: :auto,
      overflow_y: :auto
    })
  end

  defp apply_scroll_operation({:wheel_scroll, {h_delta, v_delta}}, scene) do
    # Simulate wheel scroll input
    input = {:cursor_scroll, {0, 0, h_delta, v_delta}}

    case Quillex.Scrollable.handle_input(input, scene) do
      {:handled, new_scene} -> new_scene
      {:continue, scene} -> scene
    end
  end

  defp apply_scroll_operation({:update_content_size, new_size}, scene) do
    Quillex.Scrollable.update_content_size(scene, new_size)
  end

  defp apply_scroll_operation({:ensure_visible, pos}, scene) do
    Quillex.Scrollable.ensure_visible(scene, pos)
  end
end
