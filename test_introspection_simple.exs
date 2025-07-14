# Simple test of introspection tools with running app
IO.puts "=== Testing Scene Introspection Tools ==="

try do
  # Import the DevTools
  import Scenic.DevTools
  
  # Test basic introspection
  IO.puts "\n1. Testing introspect()..."
  introspect()
  
  IO.puts "\n2. Testing architecture()..."
  architecture()
  
  IO.puts "\n3. Testing raw_scene_script()..."
  scene_data = raw_scene_script()
  IO.puts "Found #{map_size(scene_data)} scenes"
  
  # Test hierarchy extraction
  IO.puts "\n4. Testing hierarchy extraction..."
  for {key, scene} <- scene_data do
    IO.puts "Scene: #{key} | Parent: #{inspect(scene.parent)} | Depth: #{scene.depth} | Children: #{length(scene.children)}"
  end
  
  # Test text buffer discovery
  IO.puts "\n5. Testing text buffer discovery..."
  text_buffers = scene_data
  |> Map.values()
  |> Enum.flat_map(fn scene ->
    scene.elements
    |> Map.values()
    |> Enum.filter(fn element ->
      get_in(element, [:semantic, :type]) == :text_buffer
    end)
  end)
  
  IO.puts "Found #{length(text_buffers)} text buffer components"
  
  IO.puts "\n✅ All introspection tools working successfully!"
  
rescue
  error ->
    IO.puts "\n❌ Error testing introspection tools: #{inspect(error)}"
    IO.puts "\nStacktrace:"
    IO.puts Exception.format_stacktrace(__STACKTRACE__)
end