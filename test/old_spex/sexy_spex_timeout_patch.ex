defmodule SexySpex.TimeoutPatch do
  @moduledoc """
  Patch for SexySpex to add timeout handling for slow application shutdown.
  
  This module provides a timeout wrapper around Application.stop/1 to prevent
  spex tests from hanging during shutdown.
  """

  @doc """
  Stops an application with a timeout.
  
  If the application doesn't stop within the timeout period, forcefully
  terminates it and logs an error.
  
  ## Parameters
  - `app_name` - Name of the application to stop
  - `timeout_ms` - Timeout in milliseconds (default: 1000)
  
  ## Returns
  - `:ok` if stopped successfully
  - `{:error, :timeout}` if timeout occurred
  """
  def stop_application_with_timeout(app_name, timeout_ms \\ 1000) do
    IO.puts("🛑 Stopping #{String.capitalize(to_string(app_name))} (timeout: #{timeout_ms}ms)")
    
    # Start the stop operation in a separate process
    stop_task = Task.async(fn ->
      try do
        Application.stop(app_name)
        :ok
      catch
        kind, reason ->
          IO.puts("🚨 Error stopping #{app_name}: #{kind} #{inspect(reason)}")
          {:error, {kind, reason}}
      end
    end)
    
    # Wait for completion or timeout
    case Task.yield(stop_task, timeout_ms) do
      {:ok, result} ->
        IO.puts("✅ #{String.capitalize(to_string(app_name))} stopped successfully")
        result
        
      nil ->
        # Timeout occurred, forcefully shut down
        IO.puts("⏰ Timeout stopping #{app_name} after #{timeout_ms}ms - forcing shutdown")
        Task.shutdown(stop_task, :brutal_kill)
        
        # Try to forcefully stop the application
        force_stop_application(app_name)
        
        {:error, :timeout}
    end
  end

  @doc """
  Forcefully stops an application by terminating its supervision tree.
  
  This is a last resort when Application.stop/1 hangs.
  """
  def force_stop_application(app_name) do
    try do
      # Get the application master process
      case Application.get_env(app_name, :mod) do
        {module, _args} ->
          IO.puts("🔨 Force stopping #{app_name} supervision tree via #{module}")
          
          # Find and kill the application supervisor
          case Process.whereis(module) do
            nil ->
              IO.puts("⚠️  No supervisor process found for #{module}")
              
            pid when is_pid(pid) ->
              IO.puts("🔨 Killing supervisor process #{inspect(pid)}")
              Process.exit(pid, :kill)
              
              # Wait a bit for cleanup
              Process.sleep(100)
          end
          
        nil ->
          IO.puts("⚠️  No mod configuration found for #{app_name}")
      end
      
      # Also try to stop any registered processes with the app name
      case Process.whereis(app_name) do
        nil -> :ok
        pid when is_pid(pid) ->
          IO.puts("🔨 Killing main application process #{inspect(pid)}")
          Process.exit(pid, :kill)
      end
      
      # Kill any processes that might be holding up shutdown
      force_stop_scenic_processes()
      
      :ok
    catch
      kind, reason ->
        IO.puts("🚨 Error in force stop: #{kind} #{inspect(reason)}")
        {:error, {kind, reason}}
    end
  end

  defp force_stop_scenic_processes do
    # Common Scenic process names that might hang
    scenic_processes = [
      :main_viewport,
      :scenic_driver,
      :scenic_driver_local,
      QuillEx.RootScene,
      Quillex.RootScene
    ]
    
    for process_name <- scenic_processes do
      case Process.whereis(process_name) do
        nil -> :ok
        pid when is_pid(pid) ->
          IO.puts("🔨 Force killing #{process_name} process #{inspect(pid)}")
          Process.exit(pid, :kill)
      end
    end
    
    # Also kill any buffer processes
    Process.registered()
    |> Enum.filter(fn name ->
      name_str = Atom.to_string(name)
      String.contains?(name_str, "buffer") or 
      String.contains?(name_str, "Buffer") or
      String.contains?(name_str, "quillex") or
      String.contains?(name_str, "Quillex")
    end)
    |> Enum.each(fn name ->
      case Process.whereis(name) do
        nil -> :ok
        pid when is_pid(pid) ->
          IO.puts("🔨 Force killing #{name} process #{inspect(pid)}")
          Process.exit(pid, :kill)
      end
    end)
  end

  @doc """
  Creates an improved on_exit callback that uses timeout handling.
  
  This can be used as a drop-in replacement for the SexySpex on_exit callback.
  """
  def create_timeout_exit_callback(app_name, timeout_ms \\ 1000) do
    fn ->
      stop_application_with_timeout(app_name, timeout_ms)
    end
  end

  @doc """
  Monkey patch to improve SexySpex.Helpers.start_scenic_app/2
  
  This replaces the slow shutdown with a timeout-based approach.
  """
  def start_scenic_app_with_timeout(app_name, opts \\ []) do
    port = Keyword.get(opts, :port, 9999)
    timeout_retries = Keyword.get(opts, :timeout_retries, 20)
    shutdown_timeout = Keyword.get(opts, :shutdown_timeout, 1000)

    # Ensure compilation (needed when running through mix spex)
    Mix.Task.run("compile")

    # Ensure all applications are started
    case Application.ensure_all_started(app_name) do
      {:ok, _apps} ->
        IO.puts("🚀 #{String.capitalize(to_string(app_name))} started successfully")

        # Wait for MCP server to be ready
        SexySpex.Helpers.wait_for_mcp_server(port, timeout_retries)

        # Improved cleanup when tests are done
        ExUnit.Callbacks.on_exit(create_timeout_exit_callback(app_name, shutdown_timeout))

        {:ok, %{app_name: to_string(app_name), port: port}}

      {:error, reason} ->
        IO.puts("❌ Failed to start #{String.capitalize(to_string(app_name))}: #{inspect(reason)}")
        raise "Failed to start #{String.capitalize(to_string(app_name))}: #{inspect(reason)}"
    end
  end
end