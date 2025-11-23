defmodule Quillex.TestHelpers.BufferClearHelper do
  @moduledoc """
  Helper functions for reliably clearing the buffer between tests
  """
  
  alias Quillex.TestHelpers.ScriptInspector
  
  @doc """
  Reliably clear the buffer using multiple methods
  """
  def clear_buffer do
    # Method 1: Try select all + delete
    ScenicMcp.Probes.send_keys("a", [:ctrl])
    Process.sleep(50)
    ScenicMcp.Probes.send_keys("delete", [])
    Process.sleep(50)
    
    # Check if it worked
    content = ScriptInspector.get_rendered_text_string()
    if content != "" and content != nil do
      # Method 2: Try select all + backspace
      ScenicMcp.Probes.send_keys("a", [:ctrl])
      Process.sleep(50)
      ScenicMcp.Probes.send_keys("backspace", [])
      Process.sleep(50)
      
      # Check again
      content = ScriptInspector.get_rendered_text_string()
      if content != "" and content != nil do
        # Method 3: Try select all + cut
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("x", [:ctrl])
        Process.sleep(100)
        
        # Final check
        final_content = ScriptInspector.get_rendered_text_string()
        if final_content != "" and final_content != nil do
          IO.puts("WARNING: Failed to clear buffer after 3 attempts. Content: '#{final_content}'")
        end
      end
    end
  end
  
  @doc """
  Ensure buffer is empty before proceeding
  """
  def ensure_empty_buffer do
    clear_buffer()
    content = ScriptInspector.get_rendered_text_string()
    
    if content == "" or content == nil do
      :ok
    else
      {:error, "Buffer not empty: '#{content}'"}
    end
  end
end