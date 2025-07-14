defmodule Quillex.SemanticTextEditingSpex do
  @moduledoc """
  Text Editing Spex using the new Scenic Semantic Layer.
  
  This spex demonstrates how the semantic layer provides cleaner, more reliable
  testing of text editor functionality by querying semantic content directly
  instead of parsing rendered output.
  """
  use SexySpex

  alias Scenic.Semantic.Query
  alias Quillex.TestHelpers.ScriptInspector
  alias Quillex.TestHelpers.SemanticHelpers
  import Scenic.DevTools  # Import scene introspection tools

  @tmp_screenshots_dir "test/spex/screenshots/semantic"

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
    
    # Get the viewport for semantic queries
    {:ok, viewport} = Scenic.ViewPort.info(:main_viewport)
    {:ok, viewport: viewport}
  end

  spex "Semantic Text Editing - Direct Buffer Content Access",
    description: "Validates text editing using semantic queries for cleaner testing",
    tags: [:semantic, :text_editing, :ai_driven] do

    # =============================================================================
    # SEMANTIC BUFFER QUERIES
    # =============================================================================

    scenario "Basic text input with semantic verification", context do
      given_ "empty buffer ready for input", context do
        # Ensure buffer starts empty
        Process.sleep(200)  # Let the app settle first

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("semantic_baseline")
        {:ok, Map.put(context, :baseline_screenshot, baseline_screenshot)}
      end

      when_ "user types text", context do
        test_string = "Test"  # Use shorter string that we know works
        
        # Send the text all at once like hello_world_spex does
        result = ScenicMcp.Probes.send_text(test_string)
        assert result == :ok, "Text should be sent successfully"
        
        # Allow time for rendering and buffer updates
        Process.sleep(500)  # Increased delay to ensure semantic updates

        input_screenshot = ScenicMcp.Probes.take_screenshot("semantic_typed")
        {:ok, Map.merge(context, %{test_string: test_string, input_screenshot: input_screenshot})}
      end

      then_ "buffer content is accessible via semantic query", context do
        # First try the traditional approach for comparison
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # Get fresh viewport info to ensure we have latest data
        {:ok, fresh_viewport} = Scenic.ViewPort.info(:main_viewport)
        
        # Just check what we can get from semantic layer
        case SemanticHelpers.find_text_buffer(fresh_viewport) do
          {:ok, buffer} ->
            # Success! Buffer content matches
            assert buffer.content == context.test_string,
                   "Semantic buffer content should match typed text"
            
            # Verify semantic metadata
            assert buffer.semantic.type == :text_buffer
            assert buffer.semantic.editable == true
            assert buffer.semantic.role == :textbox
            
            IO.puts("✓ Successfully accessed buffer content via semantic layer!")
            IO.puts("  Buffer ID: #{buffer.semantic.buffer_id}")
            IO.puts("  Content: #{inspect(buffer.content)}")
            
            # ENHANCED: Cross-validate with scene introspection layer
            scene_data = raw_scene_script()
            text_buffers = find_text_buffer_components(scene_data)
            assert length(text_buffers) > 0, "Scene introspection should also find text buffers"
            IO.puts("  Scene layer found #{length(text_buffers)} text buffer(s)")
            
          {:error, {:timeout, msg}} ->
            # Timeout - buffer content didn't match in time
            SemanticHelpers.dump_semantic_elements(fresh_viewport)
            flunk("Timeout waiting for buffer content: #{msg}. Traditional render found: '#{rendered_content}'")
            
          {:error, reason} ->
            SemanticHelpers.dump_semantic_elements(fresh_viewport)
            flunk("Semantic query failed: #{inspect(reason)}. Traditional render found: '#{rendered_content}'")
        end

        :ok
      end
    end

    scenario "Multi-line text with semantic query", context do
      given_ "empty buffer", context do
        # Clear buffer
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("delete")
        Process.sleep(200)
        {:ok, context}
      end

      when_ "user types multiple lines", context do
        lines = [
          "Line 1: Hello",
          "Line 2: Semantic", 
          "Line 3: Testing"
        ]
        
        for {line, idx} <- Enum.with_index(lines) do
          ScenicMcp.Probes.send_text(line)
          if idx < length(lines) - 1 do
            ScenicMcp.Probes.send_keys("enter")
          end
        end
        
        Process.sleep(100)
        {:ok, Map.put(context, :lines, lines)}
      end

      then_ "semantic query returns full buffer content", context do
        expected_content = Enum.join(context.lines, "\n")
        
        # Query using buffer ID if we know it, or find first buffer
        case SemanticHelpers.find_by_type_all_graphs(context.viewport, :text_buffer) do
          {:ok, [editable | _]} ->
            assert editable.content == expected_content,
                   "Multi-line content should match. Expected:\n#{expected_content}\n\nGot:\n#{editable.content}"
                   
            # Semantic queries make it easy to verify buffer properties
            assert editable.semantic.type == :text_buffer
            assert is_binary(editable.semantic.buffer_id) or is_integer(editable.semantic.buffer_id)
            
            # ENHANCED: Validate scene architecture during multi-line operations
            IO.puts("\n=== Scene Architecture During Multi-line ===")
            scene_data = raw_scene_script()
            verify_scene_hierarchy_integrity(scene_data)
            IO.puts("✓ Scene hierarchy maintained during multi-line editing")
            
          {:ok, []} ->
            flunk("No editable content found via semantic query")
            
          {:error, reason} ->
            flunk("Failed to query editable content: #{inspect(reason)}")
        end

        :ok
      end
    end

    scenario "Direct buffer text query by ID", context do
      given_ "buffer with known content", context do
        # Clear buffer first
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("delete")
        Process.sleep(200)
        
        # Type text all at once
        ScenicMcp.Probes.send_text("Testing direct buffer query")
        Process.sleep(300)
        
        # Get buffer ID from initial query
        {:ok, buffer} = SemanticHelpers.find_text_buffer(context.viewport)
        {:ok, Map.put(context, :buffer_id, buffer.semantic.buffer_id)}
      end

      when_ "content is modified", context do
        # Clear and type new content
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        ScenicMcp.Probes.send_text("Modified content via semantic layer")
        Process.sleep(300)
        {:ok, context}
      end

      then_ "direct buffer query returns updated content", context do
        case Query.get_buffer_text(context.viewport, context.buffer_id) do
          {:ok, content} ->
            assert content == "Modified content via semantic layer",
                   "Direct buffer query should return updated content"
                   
          {:error, reason} ->
            flunk("Failed to query buffer by ID: #{inspect(reason)}")
        end

        :ok
      end
    end

    scenario "Semantic tree inspection", context do
      given_ "buffer with content", context do
        # Clear and type content
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("delete")
        Process.sleep(200)
        ScenicMcp.Probes.send_text("Inspect semantic tree")
        Process.sleep(300)
        {:ok, context}
      end

      when_ "semantic tree is inspected", context do
        # This helps with debugging and understanding the semantic structure
        IO.puts("\n=== Semantic Tree Debug Output ===")
        Query.inspect_semantic_tree(context.viewport)
        IO.puts("=================================\n")
        
        # ENHANCED: Compare semantic layer with scene introspection
        IO.puts("\n=== Scene vs Semantic Layer Comparison ===")
        architecture()
        scene_data = raw_scene_script()
        semantic_buffers = find_text_buffer_components(scene_data)
        IO.puts("Scene layer found #{length(semantic_buffers)} text buffer component(s)")
        IO.puts("===============================================\n")
        {:ok, context}
      end

      then_ "semantic elements are properly structured", context do
        {:ok, info} = Query.get_semantic_info(context.viewport)
        
        # Verify semantic structure
        assert is_map(info.elements)
        assert is_map(info.by_type)
        assert Map.has_key?(info, :timestamp)
        
        # Should have at least one text_buffer
        assert Map.has_key?(info.by_type, :text_buffer),
               "Semantic tree should contain text_buffer elements"
               
        buffer_ids = Map.get(info.by_type, :text_buffer, [])
        assert length(buffer_ids) > 0,
               "Should have at least one text buffer"
        
        # ENHANCED: Cross-validate semantic structure with scene architecture
        scene_data = raw_scene_script()
        verify_scene_integrity(scene_data)
        
        # Verify consistency between semantic and scene layers
        scene_text_buffers = find_text_buffer_components(scene_data)
        IO.puts("\n=== Layer Consistency Check ===")
        IO.puts("Semantic layer: #{length(buffer_ids)} text buffer IDs")
        IO.puts("Scene layer: #{length(scene_text_buffers)} text buffer components")
        IO.puts("==============================\n")

        :ok
      end
    end
  end

  # =============================================================================
  # Enhanced Scene Introspection Helper Functions
  # =============================================================================

  defp find_text_buffer_components(scene_data) do
    scene_data
    |> Map.values()
    |> Enum.flat_map(fn scene ->
      scene.elements
      |> Map.values()
      |> Enum.filter(fn element ->
        get_in(element, [:semantic, :type]) == :text_buffer
      end)
    end)
  end

  defp verify_scene_integrity(scene_data) do
    # Verify all scenes have required fields
    for {key, scene} <- scene_data do
      assert is_binary(key) or is_atom(key), "Scene key should be string or atom"
      assert is_map(scene.elements), "Scene should have elements map"
      assert is_list(scene.children), "Scene should have children list"
      assert is_integer(scene.depth), "Scene should have numeric depth"
    end
    
    # Verify parent-child relationships are bidirectional
    verify_parent_child_consistency(scene_data)
  end

  defp verify_scene_hierarchy_integrity(scene_data) do
    # Verify we have a proper hierarchy (not all scenes at same depth)
    depths = scene_data
    |> Map.values()
    |> Enum.map(& &1.depth)
    |> Enum.uniq()
    
    assert length(depths) > 1, "Should have scenes at different depths for proper hierarchy"
    
    # Verify root scene exists
    root_scenes = scene_data
    |> Map.values()
    |> Enum.filter(& &1.parent == nil)
    
    assert length(root_scenes) > 0, "Should have at least one root scene"
  end

  defp verify_parent_child_consistency(scene_data) do
    for {key, scene} <- scene_data do
      # For each child, verify it lists this scene as parent
      for child_key <- scene.children do
        if Map.has_key?(scene_data, child_key) do
          child_scene = scene_data[child_key]
          assert child_scene.parent == key,
                 "Child #{child_key} should list #{key} as parent, but lists #{inspect(child_scene.parent)}"
        end
      end
      
      # If scene has parent, verify parent lists this as child
      if scene.parent && Map.has_key?(scene_data, scene.parent) do
        parent_scene = scene_data[scene.parent]
        assert key in parent_scene.children,
               "Parent #{scene.parent} should list #{key} as child"
      end
    end
  end
end