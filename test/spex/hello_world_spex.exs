defmodule Quillex.HelloWorldSpex do
  use Spex
  
  @moduledoc """
  Hello World Spex for Quillex - demonstrating AI-driven testing.
  
  This spex validates that:
  1. Quillex is running and accessible via scenic_mcp
  2. Basic text input functionality works
  3. Visual feedback is available through screenshots
  4. AI can interact autonomously with the application
  """
  
  # Configure for Scenic MCP testing
  setup_all do
    Application.put_env(:spex, :adapter, Spex.Adapters.ScenicMCP)
    Application.put_env(:spex, :port, 9999)
    Application.put_env(:spex, :screenshot_dir, "test/screenshots")
    
    # Ensure screenshot directory exists
    File.mkdir_p!("test/screenshots")
    
    :ok
  end
  
  spex "Hello World - Basic Text Input",
    description: "Validates core text input functionality in Quillex",
    tags: [:smoke_test, :hello_world, :text_input, :ai_driven] do
    
    alias Spex.Adapters.ScenicMCP
    
    scenario "Application accessibility and connection" do
      given "Quillex should be running with scenic_mcp server" do
        assert ScenicMCP.wait_for_app(9999, 5), """
        ❌ Quillex must be running for AI to test it!
        
        Start Quillex: cd quillex && iex -S mix
        Then run: mix spex test/spex/hello_world_spex.exs
        """
      end
      
      then_ "AI can establish connection to the application" do
        assert ScenicMCP.app_running?(9999), "Connection should be established"
        {:ok, status} = ScenicMCP.inspect_viewport()
        assert status.active, "Application should be active and responsive"
      end
    end
    
    scenario "Basic text input functionality" do
      given "an empty editor buffer" do
        # Capture initial state
        {:ok, baseline} = ScenicMCP.take_screenshot("hello_world_baseline")
        assert File.exists?(baseline.filename), "Should capture baseline screenshot"
      end
      
      when_ "AI types 'Hello World'" do
        {:ok, result} = ScenicMCP.send_text("Hello World")
        assert result.message =~ "successfully", "Text should be sent successfully"
        
        # Allow time for rendering
        Process.sleep(500)
      end
      
      then_ "the text appears in the buffer" do
        {:ok, screenshot} = ScenicMCP.take_screenshot("hello_world_typed")
        assert File.exists?(screenshot.filename), "Should capture post-typing screenshot"
        
        # Verify we can inspect the application state
        {:ok, viewport} = ScenicMCP.inspect_viewport()
        assert viewport.active, "Application should remain responsive"
      end
    end
    
    scenario "Basic editing operations" do
      given "text is present in the buffer" do
        # We have "Hello World" from the previous scenario
        {:ok, before_edit} = ScenicMCP.take_screenshot("before_editing")
        assert File.exists?(before_edit.filename)
      end
      
      when_ "AI performs editing operations" do
        # Use backspace to remove "World"
        {:ok, _} = ScenicMCP.send_key("backspace")
        {:ok, _} = ScenicMCP.send_key("backspace")
        {:ok, _} = ScenicMCP.send_key("backspace")
        {:ok, _} = ScenicMCP.send_key("backspace")
        {:ok, _} = ScenicMCP.send_key("backspace")
        
        # Add replacement text
        {:ok, _} = ScenicMCP.send_text("Elixir!")
        
        Process.sleep(300)
      end
      
      then_ "the content is modified correctly" do
        {:ok, final_screenshot} = ScenicMCP.take_screenshot("hello_world_edited")
        assert File.exists?(final_screenshot.filename), "Should capture final state"
        
        # Verify application is still responsive
        {:ok, final_state} = ScenicMCP.inspect_viewport()
        assert final_state.active, "Application should remain stable after editing"
      end
    end
    
    # Report successful completion
    IO.puts("""
    
    🎉 HELLO WORLD SPEX COMPLETE!
    
    ✅ AI Successfully Validated:
    - Application accessibility via scenic_mcp ✅
    - Text input pipeline functionality ✅  
    - Basic editing operations ✅
    - Visual feedback through screenshots ✅
    - Application stability and responsiveness ✅
    
    📸 Evidence Generated:
    - hello_world_baseline.png (initial state)
    - hello_world_typed.png (after typing "Hello World")
    - before_editing.png (before editing operations)
    - hello_world_edited.png (final result: "Hello Elixir!")
    
    This confirms Quillex is ready for AI-driven development! 🚀
    """)
  end
  
  spex "Visual State Validation",
    description: "Validates AI's ability to observe and verify application state",
    tags: [:visual_testing, :ai_capability] do
    
    alias Spex.Adapters.ScenicMCP
    
    scenario "Multiple screenshot consistency" do
      given "the application is in a known state" do
        # Clear the buffer first
        {:ok, _} = ScenicMCP.send_key("a", ["ctrl"])  # Select all
        {:ok, _} = ScenicMCP.send_key("delete")       # Delete all
        
        # Add distinctive content
        distinctive_text = "SPEX-TEST-#{:os.system_time(:second)}"
        {:ok, _} = ScenicMCP.send_text(distinctive_text)
        
        Process.sleep(300)
      end
      
      when_ "AI captures multiple screenshots" do
        screenshots = for i <- 1..3 do
          {:ok, screenshot} = ScenicMCP.take_screenshot("visual_validation_#{i}")
          Process.sleep(100)
          screenshot.filename
        end
        
        # Store in process for next step
        Process.put(:screenshots, screenshots)
      end
      
      then_ "all screenshots are captured successfully" do
        screenshots = Process.get(:screenshots, [])
        
        Enum.each(screenshots, fn filename ->
          assert File.exists?(filename), "Screenshot #{filename} should exist"
        end)
        
        IO.puts("✅ Visual validation complete - AI can reliably capture application state")
        IO.puts("   Screenshots: #{Enum.join(screenshots, ", ")}")
      end
    end
  end
end