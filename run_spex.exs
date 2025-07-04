#!/usr/bin/env elixir

defmodule SpexRunner do
  @moduledoc """
  Simple runner for Quillex spex files.
  Executes specifications and generates reports.
  """
  
  def run(spex_file) do
    IO.puts("🚀 Running Spex: #{spex_file}")
    IO.puts("=" |> String.duplicate(50))
    
    start_time = :os.system_time(:millisecond)
    
    try do
      # Load and run the spex file
      Code.require_file(spex_file)
      
      # Run ExUnit to execute the tests
      ExUnit.start()
      ExUnit.run()
      
      end_time = :os.system_time(:millisecond)
      duration = end_time - start_time
      
      IO.puts("""
      
      🎉 Spex execution completed!
      Duration: #{duration}ms
      
      For detailed results, check the test output above.
      Screenshots and evidence files are saved in the current directory.
      """)
      
    rescue
      error ->
        IO.puts("❌ Spex execution failed: #{inspect(error)}")
        System.halt(1)
    end
  end
end

# Run the hello world spex if this script is executed directly
if System.argv() != [] do
  [spex_file | _] = System.argv()
  SpexRunner.run(spex_file)
else
  SpexRunner.run("spex/hello_world_spex.exs")
end