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
        ScenicMcp.Probes.send_keys("a", [:ctrl])  # Clear any existing content
        Process.sleep(50)

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("semantic_baseline")
        {:ok, Map.put(context, :baseline_screenshot, baseline_screenshot)}
      end

      when_ "user types text", context do
        test_string = "Hello Semantic World!"
        ScenicMcp.Probes.send_text(test_string)
        Process.sleep(100)

        input_screenshot = ScenicMcp.Probes.take_screenshot("semantic_typed")
        {:ok, Map.merge(context, %{test_string: test_string, input_screenshot: input_screenshot})}
      end

      then_ "buffer content is accessible via semantic query", context do
        # First try the traditional approach for comparison
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # Now use semantic query - find the first text buffer
        case Query.find_by_type(context.viewport, :text_buffer) do
          {:ok, [buffer | _]} ->
            # Direct access to buffer content!
            assert buffer.content == context.test_string,
                   "Semantic buffer content should match typed text. Expected: '#{context.test_string}', Got: '#{buffer.content}'"
            
            # Verify semantic metadata
            assert buffer.semantic.type == :text_buffer
            assert buffer.semantic.editable == true
            assert buffer.semantic.role == :textbox
            
            IO.puts("✓ Successfully accessed buffer content via semantic layer!")
            IO.puts("  Buffer ID: #{buffer.semantic.buffer_id}")
            IO.puts("  Content: #{inspect(buffer.content)}")
            
          {:ok, []} ->
            flunk("No text buffers found via semantic query. Traditional render found: '#{rendered_content}'")
            
          {:error, reason} ->
            flunk("Semantic query failed: #{inspect(reason)}. Traditional render found: '#{rendered_content}'")
        end

        :ok
      end
    end

    scenario "Multi-line text with semantic query", context do
      given_ "empty buffer", context do
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
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
        case Query.get_editable_content(context.viewport) do
          {:ok, [editable | _]} ->
            assert editable.content == expected_content,
                   "Multi-line content should match. Expected:\n#{expected_content}\n\nGot:\n#{editable.content}"
                   
            # Semantic queries make it easy to verify buffer properties
            assert editable.type == :text_buffer
            assert is_binary(editable.buffer_id) or is_integer(editable.buffer_id)
            
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
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        
        ScenicMcp.Probes.send_text("Testing direct buffer query")
        Process.sleep(100)
        
        # Get buffer ID from initial query
        {:ok, [buffer | _]} = Query.find_by_type(context.viewport, :text_buffer)
        {:ok, Map.put(context, :buffer_id, buffer.semantic.buffer_id)}
      end

      when_ "content is modified", context do
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        ScenicMcp.Probes.send_text("Modified content via semantic layer")
        Process.sleep(100)
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
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        ScenicMcp.Probes.send_text("Inspect semantic tree")
        Process.sleep(100)
        {:ok, context}
      end

      when_ "semantic tree is inspected", context do
        # This helps with debugging and understanding the semantic structure
        IO.puts("\n=== Semantic Tree Debug Output ===")
        Query.inspect_semantic_tree(context.viewport)
        IO.puts("=================================\n")
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

        :ok
      end
    end
  end
end