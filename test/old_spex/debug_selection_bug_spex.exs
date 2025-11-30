defmodule Quillex.DebugSelectionBugSpex do
  @moduledoc """
  Debug the actual selection bug that the user can reproduce manually.
  This test will type text during selection to expose the bug behavior.
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  # Helper function for reliable buffer clearing
  defp clear_buffer_reliable() do
    ScenicMcp.Probes.send_keys("a", [:ctrl])
    Process.sleep(50)
    ScenicMcp.Probes.send_keys("delete", [])
    Process.sleep(50)
  end

  spex "Debug Selection Bug - Manual Reproduction",
    description: "Reproduce the selection bug that the user can trigger manually",
    tags: [:debug, :selection, :manual_reproduction] do

    scenario "Selection bug - Right+Right+Left+Left creates wrong selection", context do
      given_ "clean text content", context do
        clear_buffer_reliable()
        
        test_text = "Hello world selection test"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        # Position cursor after "Hello " (position 6)
        ScenicMcp.Probes.send_keys("home")
        Process.sleep(50)
        # Move right 6 times to get after "Hello "
        for _i <- 1..6 do
          ScenicMcp.Probes.send_keys("right")
          Process.sleep(20)
        end
        Process.sleep(100)

        initial_content = ScriptInspector.get_rendered_text_string()
        IO.puts("\n🎯 INITIAL STATE:")
        IO.puts("Content: '#{initial_content}'")
        IO.puts("Cursor should be after 'Hello ' (between 'o' and 'w')")
        
        {:ok, Map.put(context, :initial_content, initial_content)}
      end

      when_ "user does Shift+Right twice then Shift+Left twice", context do
        IO.puts("\n🔍 PERFORMING SELECTION OPERATIONS:")
        
        # Step 1: First Shift+Right (should start selecting "w")
        IO.puts("Step 1: Shift+Right (should select 'w')")
        ScenicMcp.Probes.send_keys("right", ["shift"])
        Process.sleep(100)
        
        after_1_right = ScriptInspector.get_rendered_text_string()
        IO.puts("After 1 Shift+Right: '#{after_1_right}'")
        
        # Step 2: Second Shift+Right (should extend selection to "wo")
        IO.puts("\nStep 2: Shift+Right (should extend selection to 'wo')")
        ScenicMcp.Probes.send_keys("right", ["shift"])
        Process.sleep(100)
        
        after_2_right = ScriptInspector.get_rendered_text_string()
        IO.puts("After 2 Shift+Right: '#{after_2_right}'")
        
        # Step 3: First Shift+Left (should reduce selection back to "w")
        IO.puts("\nStep 3: Shift+Left (should reduce selection to 'w')")
        ScenicMcp.Probes.send_keys("left", ["shift"])
        Process.sleep(100)
        
        after_1_left = ScriptInspector.get_rendered_text_string()
        IO.puts("After 1 Shift+Left: '#{after_1_left}'")
        
        # Step 4: Second Shift+Left (should cancel selection entirely)
        IO.puts("\nStep 4: Shift+Left (should cancel selection completely)")
        ScenicMcp.Probes.send_keys("left", ["shift"])
        Process.sleep(100)
        
        after_2_left = ScriptInspector.get_rendered_text_string()
        IO.puts("After 2 Shift+Left: '#{after_2_left}'")
        
        {:ok, Map.merge(context, %{
          after_1_right: after_1_right,
          after_2_right: after_2_right,
          after_1_left: after_1_left,
          after_2_left: after_2_left
        })}
      end

      and_ "user types replacement text to expose selection state", context do
        IO.puts("\n🧪 TESTING SELECTION STATE BY TYPING:")
        IO.puts("If there's an active selection, typing should replace the selected text")
        IO.puts("If no selection, typing should insert at cursor position")
        
        # Type a test character to see what happens
        test_char = "X"
        ScenicMcp.Probes.send_text(test_char)
        Process.sleep(100)
        
        final_content = ScriptInspector.get_rendered_text_string()
        IO.puts("After typing '#{test_char}': '#{final_content}'")
        
        {:ok, Map.put(context, :final_content, final_content)}
      end

      then_ "analyze the actual selection behavior", context do
        IO.puts("\n📊 SELECTION BUG ANALYSIS:")
        IO.puts("Expected behavior: After Right+Right+Left+Left with Shift, cursor should be back at original position")
        IO.puts("Expected result after typing 'X': 'Hello Xworld selection test' (X inserted between Hello and world)")
        
        IO.puts("\n🔍 Step-by-step analysis:")
        IO.puts("1. Initial: '#{context.initial_content}'")
        IO.puts("2. After 1 Shift+Right: '#{context.after_1_right}'")
        IO.puts("3. After 2 Shift+Right: '#{context.after_2_right}'")
        IO.puts("4. After 1 Shift+Left: '#{context.after_1_left}'")
        IO.puts("5. After 2 Shift+Left: '#{context.after_2_left}'")
        IO.puts("6. After typing 'X': '#{context.final_content}'")
        
        # Analyze what actually happened
        expected_if_correct = "Hello Xworld selection test"
        
        if context.final_content == expected_if_correct do
          IO.puts("\n✅ SELECTION BEHAVIOR IS CORRECT")
          IO.puts("Cursor returned to original position, selection was properly cancelled")
        else
          IO.puts("\n🐛 SELECTION BUG CONFIRMED!")
          IO.puts("Expected: '#{expected_if_correct}'")
          IO.puts("Actual: '#{context.final_content}'")
          
          # Analyze the specific type of bug
          cond do
            String.contains?(context.final_content, "Xello") ->
              IO.puts("🐛 BUG TYPE: Cursor moved too far left - selected text to the left of original position")
              
            String.contains?(context.final_content, "orld selection test") and not String.contains?(context.final_content, "world") ->
              IO.puts("🐛 BUG TYPE: Selection included 'w' - didn't properly cancel selection")
              
            String.length(context.final_content) < String.length(context.initial_content) ->
              IO.puts("🐛 BUG TYPE: Text was deleted - selection state caused unwanted deletion")
              
            true ->
              IO.puts("🐛 BUG TYPE: Unknown selection behavior - unexpected result")
          end
        end
        
        # Assert that the selection behavior is correct
        assert context.final_content == expected_if_correct,
               "Selection bug detected! Expected cursor at original position after Right+Right+Left+Left. Expected: '#{expected_if_correct}', Got: '#{context.final_content}'"
        
        :ok
      end
    end
  end
end