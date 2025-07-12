defmodule ProfileOperations do
  @moduledoc """
  Profile the execution time of key operations to find bottlenecks.
  """

  def profile do
    # Start the app manually without SexySpex
    Application.ensure_all_started(:quillex)
    Process.sleep(1000)
    
    IO.puts("\n=== Profiling Key Operations ===\n")
    
    # Profile individual operations
    profile_operation("Send single key", fn ->
      ScenicMcp.Probes.send_keys("a", [])
    end)
    
    profile_operation("Send text", fn ->
      ScenicMcp.Probes.send_text("Hello")
    end)
    
    profile_operation("Select all (Ctrl+A)", fn ->
      ScenicMcp.Probes.send_keys("a", ["ctrl"])
    end)
    
    profile_operation("Copy (Ctrl+C)", fn ->
      ScenicMcp.Probes.send_keys("c", ["ctrl"])
    end)
    
    # Profile the problematic sequence
    IO.puts("\n=== Profiling Rapid Sequence ===\n")
    
    # Setup some text
    ScenicMcp.Probes.send_text("Test text for profiling")
    Process.sleep(100)
    
    profile_operation("Rapid Ctrl+A then Ctrl+C", fn ->
      ScenicMcp.Probes.send_keys("a", ["ctrl"])
      ScenicMcp.Probes.send_keys("c", ["ctrl"])
    end)
    
    # Now with a delay
    profile_operation("Ctrl+A, 25ms delay, Ctrl+C", fn ->
      ScenicMcp.Probes.send_keys("a", ["ctrl"])
      Process.sleep(25)
      ScenicMcp.Probes.send_keys("c", ["ctrl"])
    end)
    
    # Profile clipboard directly
    IO.puts("\n=== Profiling Clipboard Operations ===\n")
    
    profile_operation("Clipboard.copy/1", fn ->
      Clipboard.copy("Test clipboard content")
    end)
    
    profile_operation("Clipboard.paste/0", fn ->
      Clipboard.paste()
    end)
    
    # Check message queue sizes
    check_process_queues()
  end

  defp profile_operation(name, fun) do
    # Warm up
    fun.()
    Process.sleep(50)
    
    # Time multiple runs
    times = for _ <- 1..5 do
      start = System.monotonic_time(:microsecond)
      fun.()
      stop = System.monotonic_time(:microsecond)
      stop - start
    end
    
    avg = Enum.sum(times) / length(times)
    min = Enum.min(times)
    max = Enum.max(times)
    
    IO.puts("#{name}:")
    IO.puts("  Average: #{Float.round(avg / 1000, 2)}ms")
    IO.puts("  Min: #{Float.round(min / 1000, 2)}ms")
    IO.puts("  Max: #{Float.round(max / 1000, 2)}ms")
    IO.puts("")
  end

  defp check_process_queues do
    IO.puts("\n=== Process Message Queue Sizes ===\n")
    
    processes = [
      {:main_viewport, Process.whereis(:main_viewport)},
      {:scenic_driver, Process.whereis(:scenic_driver)}
    ]
    
    # Find buffer processes
    buffer_procs = Process.registered()
    |> Enum.filter(fn name -> 
      name |> Atom.to_string() |> String.contains?("buffer")
    end)
    |> Enum.map(fn name -> {name, Process.whereis(name)} end)
    
    all_procs = processes ++ buffer_procs
    
    for {name, pid} <- all_procs, is_pid(pid) do
      {:message_queue_len, len} = Process.info(pid, :message_queue_len)
      IO.puts("#{name}: #{len} messages in queue")
    end
  end
end

# Run the profiling
ProfileOperations.profile()