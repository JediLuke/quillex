defmodule TraceRapidOps do
  @moduledoc """
  Trace the rapid operations test to understand timing bottlenecks.
  Uses Erlang's built-in tracing capabilities.
  """

  def trace_test do
    # Start tracing
    setup_tracing()
    
    # Run a simplified version of the rapid operations test
    IO.puts("\n=== Starting traced rapid operations test ===\n")
    
    # Connect to Quillex
    Process.sleep(1000)  # Give app time to start
    
    # Trace the rapid sequence
    trace_point("Starting rapid sequence")
    
    # Type "Rapid"
    trace_point("Sending text: Rapid")
    ScenicMcp.Probes.send_text("Rapid")
    
    trace_point("Sending HOME key")
    ScenicMcp.Probes.send_keys("home", [])
    
    # Select "Rapid" with shift+right
    trace_point("Starting selection")
    for i <- 1..5 do
      trace_point("Sending shift+right #{i}")
      ScenicMcp.Probes.send_keys("right", ["shift"])
    end
    
    # Replace with "FAST"
    trace_point("Sending replacement text: FAST")
    ScenicMcp.Probes.send_text("FAST")
    
    # Select all
    trace_point("Sending Ctrl+A")
    ScenicMcp.Probes.send_keys("a", ["ctrl"])
    
    # Copy
    trace_point("Sending Ctrl+C")
    ScenicMcp.Probes.send_keys("c", ["ctrl"])
    
    # Move to end
    trace_point("Sending END key")
    ScenicMcp.Probes.send_keys("end", [])
    
    # Add space
    trace_point("Sending space")
    ScenicMcp.Probes.send_text(" ")
    
    # Paste
    trace_point("Sending Ctrl+V")
    ScenicMcp.Probes.send_keys("v", ["ctrl"])
    
    # Wait a bit to see results
    Process.sleep(500)
    
    trace_point("Test complete")
    
    # Stop tracing and analyze
    stop_tracing()
  end

  defp setup_tracing do
    # Trace function calls for key modules
    :erlang.trace(:all, true, [:call, :timestamp, :return_to])
    
    # Trace scenic input handling
    :erlang.trace_pattern({ViewPort.Input, :send, 2}, [{:_, [], [{:return_trace}]}], [])
    :erlang.trace_pattern({ViewPort, :handle_cast, 2}, [{:_, [], [{:return_trace}]}], [])
    
    # Trace Quillex buffer operations
    :erlang.trace_pattern({Quillex.Buffer.Process.Reducer, :process, 2}, [{:_, [], [{:return_trace}]}], [])
    :erlang.trace_pattern({Quillex.GUI.Components.BufferPane.Mutator, :_, :_}, [{:_, [], [{:return_trace}]}], [])
    
    # Trace clipboard operations
    :erlang.trace_pattern({Clipboard, :copy, 1}, [{:_, [], [{:return_trace}]}], [])
    :erlang.trace_pattern({Clipboard, :paste, 0}, [{:_, [], [{:return_trace}]}], [])
    
    # Trace MCP communication
    :erlang.trace_pattern({ScenicMcp.Probes, :_, :_}, [{:_, [], [{:return_trace}]}], [])
    
    # Start collecting traces
    spawn(fn -> collect_traces() end)
  end

  defp collect_traces do
    receive do
      {:trace_ts, pid, :call, {module, function, args}, timestamp} ->
        log_trace(:call, pid, module, function, args, timestamp)
        collect_traces()
        
      {:trace_ts, pid, :return_from, {module, function, arity}, return_value, timestamp} ->
        log_trace(:return, pid, module, function, arity, timestamp, return_value)
        collect_traces()
        
      :stop ->
        :ok
    end
  end

  defp log_trace(:call, pid, module, function, args, {mega, secs, micro}) do
    time = mega * 1_000_000 + secs + micro / 1_000_000
    IO.puts("[#{format_time(time)}] CALL #{inspect(pid)} #{module}.#{function}(#{inspect_args(args)})")
  end

  defp log_trace(:return, pid, module, function, arity, {mega, secs, micro}, return_value) do
    time = mega * 1_000_000 + secs + micro / 1_000_000
    IO.puts("[#{format_time(time)}] RETURN #{inspect(pid)} #{module}.#{function}/#{arity} => #{inspect(return_value)}")
  end

  defp inspect_args(args) do
    args
    |> Enum.map(&inspect/1)
    |> Enum.join(", ")
  end

  defp format_time(time) do
    Float.round(time, 6)
  end

  defp trace_point(message) do
    {mega, secs, micro} = :os.timestamp()
    time = mega * 1_000_000 + secs + micro / 1_000_000
    IO.puts("\n>>> [#{format_time(time)}] #{message}")
  end

  defp stop_tracing do
    :erlang.trace(:all, false, [:call, :timestamp, :return_to])
    send(Process.whereis(:trace_collector), :stop)
  end
end

# Register the trace collector
Process.register(self(), :trace_collector)

# Start Quillex and run the traced test
{:ok, _} = SexySpex.Helpers.start_scenic_app(:quillex)
Process.sleep(1000)

TraceRapidOps.trace_test()