#!/usr/bin/env elixir

# Simple test script to verify semantic layer integration in Quillex
# Run with: elixir test_semantic.exs

# Make sure scenic_local is available
Code.prepend_path("../scenic_local/_build/dev/lib/scenic/ebin")
Code.prepend_path("_build/dev/lib/quillex/ebin")
Code.prepend_path("../scenic_local/_build/dev/lib/nimble_options/ebin")
Code.prepend_path("../scenic_local/_build/dev/lib/truetype_metrics/ebin")
Code.prepend_path("../scenic_local/_build/dev/lib/font_metrics/ebin")
Code.prepend_path("../scenic_local/_build/dev/lib/ex_image_info/ebin")

# Start necessary applications and Scenic supervisor
{:ok, _} = Scenic.start_link([])

# Create a test viewport
{:ok, viewport} = Scenic.ViewPort.start([
  name: :test_viewport,
  size: {800, 600},
  default_scene: {Scenic.Scene, nil}
])

# Test 1: Basic semantic annotation
IO.puts("\n=== Test 1: Basic Semantic Annotation ===")

# Use a simple graph without text primitives to avoid font issues
graph = 
  Scenic.Graph.build()
  |> Scenic.Primitives.rect({100, 40}, 
       fill: :blue,
       semantic: %{type: :button, label: "Click Me"})

# Put the graph
Scenic.ViewPort.put_graph(viewport, :test_graph, graph)

# Query semantic info
case Scenic.Semantic.Query.get_semantic_info(viewport, :test_graph) do
  {:ok, info} ->
    IO.puts("✓ Semantic info stored successfully!")
    IO.puts("  Elements: #{map_size(info.elements)}")
    IO.puts("  Types: #{inspect(Map.keys(info.by_type))}")
    
  {:error, reason} ->
    IO.puts("✗ Failed to get semantic info: #{inspect(reason)}")
end

# Test 2: Query by type (buttons only since we don't have text buffers)
IO.puts("\n=== Test 2: Query by Type ===")

case Scenic.Semantic.Query.find_by_type(viewport, :button, :test_graph) do
  {:ok, buttons} ->
    IO.puts("✓ Found #{length(buttons)} button(s)")
    for button <- buttons do
      IO.puts("  Button label: #{button.semantic.label}")
    end
    
  {:error, reason} ->
    IO.puts("✗ Failed to query buttons: #{inspect(reason)}")
end

# Test 4: Button query
IO.puts("\n=== Test 4: Button Query ===")

case Scenic.Semantic.Query.get_button_by_label(viewport, "Click Me", :test_graph) do
  {:ok, button} ->
    IO.puts("✓ Found button: #{inspect(button.semantic.label)}")
    
  {:error, reason} ->
    IO.puts("✗ Failed to find button: #{inspect(reason)}")
end

# Clean up
Scenic.ViewPort.stop(viewport)

IO.puts("\n✓ All tests completed!")