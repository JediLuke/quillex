defmodule TraceMessageFlow do
  @moduledoc """
  Trace message flow through the system to understand timing.
  Uses recon library for better tracing if available, falls back to erlang trace.
  """

  def run do
    IO.puts("\n=== Setting up message flow tracing ===\n")
    
    # Start the app
    {:ok, _} = SexySpex.Helpers.start_scenic_app(:quillex)
    Process.sleep(1000)
    
    # Set up tracing
    setup_message_tracing()
    
    # Run the problematic sequence
    IO.puts("\n=== Running rapid sequence ===\n")
    timestamp("START")
    
    # The problematic rapid sequence
    timestamp("Sending Ctrl+A")
    ScenicMcp.Probes.send_keys("a", ["ctrl"])
    
    timestamp("Sending Ctrl+C") 
    ScenicMcp.Probes.send_keys("c", ["ctrl"])
    
    timestamp("Waiting 200ms")
    Process.sleep(200)
    
    timestamp("DONE")
    
    # Collect and display results
    Process.sleep(500)
    analyze_results()
  end

  defp setup_message_tracing do
    # Trace all messages to key processes
    viewport_pid = Process.whereis(:main_viewport)
    driver_pid = Process.whereis(:scenic_driver)
    
    if viewport_pid do
      :erlang.trace(viewport_pid, true, [:receive, :send, :procs, :timestamp])
      IO.puts("Tracing ViewPort: #{inspect(viewport_pid)}")
    end
    
    if driver_pid do
      :erlang.trace(driver_pid, true, [:receive, :send, :procs, :timestamp])
      IO.puts("Tracing Driver: #{inspect(driver_pid)}")
    end
    
    # Trace buffer processes
    buffer_procs = Process.registered()
    |> Enum.filter(fn name -> 
      name |> Atom.to_string() |> String.contains?("buffer")
    end)
    |> Enum.map(&Process.whereis/1)
    |> Enum.filter(&is_pid/1)
    
    for pid <- buffer_procs do
      :erlang.trace(pid, true, [:receive, :send, :timestamp])
      IO.puts("Tracing Buffer process: #{inspect(pid)}")
    end
    
    # Start trace collector
    collector = spawn(fn -> collect_traces([]) end)
    Process.register(collector, :trace_collector)
  end

  defp collect_traces(acc) do
    receive do
      {:trace_ts, pid, :receive, msg, ts} ->
        trace = {:receive, pid, msg, ts}
        collect_traces([trace | acc])
        
      {:trace_ts, pid, :send, msg, to, ts} ->
        trace = {:send, pid, to, msg, ts}
        collect_traces([trace | acc])
        
      {:trace_ts, pid, type, data, ts} when type in [:spawn, :exit] ->
        trace = {type, pid, data, ts}
        collect_traces([trace | acc])
        
      {:get_traces, from} ->
        send(from, {:traces, Enum.reverse(acc)})
        collect_traces(acc)
        
      :stop ->
        :ok
    end
  end

  defp timestamp(label) do
    {mega, secs, micro} = :os.timestamp()
    ms = div(mega * 1_000_000_000_000 + secs * 1_000_000 + micro, 1000)
    IO.puts("[#{ms}ms] #{label}")
  end

  defp analyze_results do
    # Get traces
    send(Process.whereis(:trace_collector), {:get_traces, self()})
    
    traces = receive do
      {:traces, traces} -> traces
    after
      1000 -> []
    end
    
    IO.puts("\n=== Message Flow Analysis ===\n")
    IO.puts("Total messages traced: #{length(traces)}")
    
    # Group by message type
    ctrl_a_msgs = traces |> Enum.filter(fn
      {_, _, _, msg, _} -> msg |> inspect() |> String.contains?("key_a")
      _ -> false
    end)
    
    ctrl_c_msgs = traces |> Enum.filter(fn
      {_, _, _, msg, _} -> msg |> inspect() |> String.contains?("key_c")
      _ -> false
    end)
    
    IO.puts("Ctrl+A related messages: #{length(ctrl_a_msgs)}")
    IO.puts("Ctrl+C related messages: #{length(ctrl_c_msgs)}")
    
    # Show timing between key events
    if length(ctrl_a_msgs) > 0 and length(ctrl_c_msgs) > 0 do
      {_, _, _, _, ts1} = List.first(ctrl_a_msgs)
      {_, _, _, _, ts2} = List.first(ctrl_c_msgs)
      
      time_diff = timestamp_diff(ts1, ts2)
      IO.puts("\nTime between Ctrl+A and Ctrl+C messages: #{time_diff}ms")
    end
    
    # Show detailed flow for Ctrl+A
    IO.puts("\n=== Ctrl+A Message Flow ===")
    ctrl_a_msgs
    |> Enum.take(10)
    |> Enum.each(&print_trace/1)
    
    # Clean up
    :erlang.trace(:all, false, :all)
    send(Process.whereis(:trace_collector), :stop)
  end

  defp timestamp_diff({m1, s1, u1}, {m2, s2, u2}) do
    t1 = m1 * 1_000_000_000 + s1 * 1_000 + div(u1, 1000)
    t2 = m2 * 1_000_000_000 + s2 * 1_000 + div(u2, 1000)
    abs(t2 - t1)
  end

  defp print_trace({:receive, pid, msg, {mega, secs, micro}}) do
    ms = div(mega * 1_000_000_000_000 + secs * 1_000_000 + micro, 1000)
    IO.puts("  [#{ms}ms] #{inspect(pid)} RECEIVED: #{inspect(msg, limit: 2)}")
  end

  defp print_trace({:send, from, to, msg, {mega, secs, micro}}) do
    ms = div(mega * 1_000_000_000_000 + secs * 1_000_000 + micro, 1000)
    IO.puts("  [#{ms}ms] #{inspect(from)} -> #{inspect(to)}: #{inspect(msg, limit: 2)}")
  end

  defp print_trace({type, pid, data, {mega, secs, micro}}) do
    ms = div(mega * 1_000_000_000_000 + secs * 1_000_000 + micro, 1000)
    IO.puts("  [#{ms}ms] #{type} #{inspect(pid)}: #{inspect(data, limit: 2)}")
  end
end

# Run the trace
TraceMessageFlow.run()