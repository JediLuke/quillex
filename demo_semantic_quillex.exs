#!/usr/bin/env elixir

# Demonstration of Scenic Semantic Layer with Quillex
# This shows how the semantic layer provides clean access to buffer content

# Note: Run this from the quillex directory
# First start Quillex with: iex -S mix

IO.puts("""
==============================================
Scenic Semantic Layer Demo with Quillex
==============================================

This demonstrates how the semantic layer provides:
1. Direct access to buffer content without parsing scripts
2. Semantic metadata for testing and accessibility
3. Clean query APIs for test automation

To see it in action:
1. Start Quillex in another terminal: iex -S mix
2. Type some text in the editor
3. Run this script to query the buffer content

Press Enter when Quillex is running and you've typed some text...
""")

IO.gets("")

# Connect to the running Quillex viewport
case Process.whereis(:main_viewport) do
  nil ->
    IO.puts("❌ Error: Quillex is not running. Please start it with: iex -S mix")
    System.halt(1)
    
  _pid ->
    # Get the viewport info
    {:ok, viewport} = Scenic.ViewPort.info(:main_viewport)
    
    IO.puts("\n✅ Connected to Quillex viewport!")
    
    # Debug: Inspect the semantic tree
    IO.puts("\n=== Semantic Tree Overview ===")
    Scenic.Semantic.Query.inspect_semantic_tree(viewport)
    
    # Query for text buffers
    IO.puts("\n=== Querying Text Buffers ===")
    
    case Scenic.Semantic.Query.find_by_type(viewport, :text_buffer) do
      {:ok, buffers} when length(buffers) > 0 ->
        IO.puts("✓ Found #{length(buffers)} text buffer(s)")
        
        for buffer <- buffers do
          IO.puts("\n📝 Buffer Information:")
          IO.puts("  ID: #{buffer.semantic.buffer_id}")
          IO.puts("  Editable: #{buffer.semantic.editable}")
          IO.puts("  Role: #{buffer.semantic.role}")
          IO.puts("  Content Preview:")
          
          content = buffer.content || ""
          lines = String.split(content, "\n")
          preview_lines = Enum.take(lines, 5)
          
          Enum.with_index(preview_lines, 1)
          |> Enum.each(fn {line, num} ->
            IO.puts("    #{num}: #{line}")
          end)
          
          if length(lines) > 5 do
            IO.puts("    ... (#{length(lines) - 5} more lines)")
          end
        end
        
      {:ok, []} ->
        IO.puts("""
        ⚠️  No text buffers found with semantic metadata.
        
        This could mean:
        1. The buffer pane hasn't been rendered yet
        2. The semantic annotation hasn't been added to the buffer
        
        Make sure you're running the version of Quillex with semantic support.
        """)
        
      {:error, reason} ->
        IO.puts("❌ Error querying text buffers: #{inspect(reason)}")
    end
    
    # Query all editable content
    IO.puts("\n=== All Editable Content ===")
    
    case Scenic.Semantic.Query.get_editable_content(viewport) do
      {:ok, editable} when length(editable) > 0 ->
        IO.puts("✓ Found #{length(editable)} editable element(s)")
        
        for elem <- editable do
          IO.puts("  Type: #{elem.type}, Buffer ID: #{elem.buffer_id}")
        end
        
      {:ok, []} ->
        IO.puts("  No editable content found")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
    
    IO.puts("""
    
    ==============================================
    Demo Complete!
    
    The semantic layer provides:
    - Direct buffer content access
    - No need to parse rendering scripts
    - Clean API for test automation
    - Foundation for accessibility features
    ==============================================
    """)
end