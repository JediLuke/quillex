defmodule Mix.Tasks.RunSpex do
  @shortdoc "Run QuillEx spex integration tests with GLFW Scenic driver"
  @moduledoc """
  Runs the QuillEx spex integration tests with the GLFW Scenic driver.

  This is a convenience wrapper around `mix spex` that ensures the
  `SCENIC_LOCAL_TARGET` environment variable is set to `"glfw"`, which is
  required for the Scenic GUI to open a window and render on a desktop.

  It also starts `tools/window_pinner` before the tests and stops it
  afterward, pinning Quillex windows to the current X11 desktop so that
  test windows do not appear on other workspaces. The pinner is skipped
  gracefully if the binary is absent or `DISPLAY` is unset (headless/CI).

  ## Usage

      mix run_spex
      mix run_spex test/spex/quillex/01_app_launch_spex.exs
      mix run_spex --trace
      mix run_spex --verbose

  All arguments are forwarded verbatim to `mix spex`.

  ## Environment

  Sets `SCENIC_LOCAL_TARGET=glfw` unless the variable is already present in
  the process environment.  This prevents overriding a caller-supplied value,
  so you can still do:

      SCENIC_LOCAL_TARGET=headless mix run_spex  # override to headless

  ## Examples

      # Run full spex suite
      mix run_spex

      # Run a single spec file
      mix run_spex test/spex/quillex/02_basic_text_editing_spex.exs

      # Run with verbose output
      mix run_spex --verbose

      # Run with explicit JSONL failure output
      mix run_spex --jsonl spex_failures.jsonl

  ## Notes

  The underlying `mix spex` command is provided by the `sexy_spex` library.
  See `mix help spex` for the full list of supported flags.
  """

  use Boundary, classify_to: Quillex.Mix
  use Mix.Task

  # Declare the preferred CLI environment at the task level so that
  # `mix run_spex` always runs in :test regardless of whether the caller's
  # mix.exs has `preferred_cli_env: [run_spex: :test]` configured.
  @preferred_cli_env :test

  @impl true
  def run(args) do
    maybe_set_scenic_target()
    pinner_port = maybe_start_window_pinner()

    try do
      # Delegate to mix spex, passing through all CLI arguments unchanged.
      Mix.Task.run("spex", args)
    after
      stop_window_pinner(pinner_port)
    end
  end

  @doc """
  Sets `SCENIC_LOCAL_TARGET` to `"glfw"` if the variable is not already present
  in the process environment.

  Extracted as a named function so that unit tests can exercise the actual
  env-setting logic directly, rather than duplicating it in the test file.
  """
  def maybe_set_scenic_target do
    unless System.get_env("SCENIC_LOCAL_TARGET") do
      System.put_env("SCENIC_LOCAL_TARGET", "glfw")
    end
  end

  @doc """
  Starts `tools/window_pinner` if the binary exists and `DISPLAY` is set.

  Returns an open `Port` on success, or `nil` if the binary is missing or
  the environment is headless (no `DISPLAY`). Pass the result to
  `stop_window_pinner/1` when tests complete.

  The pinner is an event-driven X11 daemon that watches for Quillex windows
  and moves them to whichever desktop was active when it started. This keeps
  spex test windows from popping up on the wrong workspace during
  multi-desktop development sessions.
  """
  def maybe_start_window_pinner do
    pinner_path = Path.join([File.cwd!(), "tools", "window_pinner"])

    cond do
      not File.exists?(pinner_path) ->
        Mix.shell().info("  window_pinner not found at tools/window_pinner, skipping desktop pinning")
        nil

      System.get_env("DISPLAY") in [nil, ""] ->
        Mix.shell().info("  No DISPLAY set, skipping window_pinner (headless environment)")
        nil

      true ->
        Mix.shell().info("  Starting window_pinner (pinning Quillex windows to current desktop)...")
        Port.open({:spawn_executable, pinner_path}, [:binary, :exit_status, :stderr_to_stdout])
    end
  end

  @doc """
  Stops the window_pinner port, if one is running.

  Accepts `nil` (no-op) or an open `Port`. Retrieves the OS PID via
  `Port.info/1`, closes the port, then sends SIGTERM to the OS process.
  This is necessary because window_pinner blocks on `XNextEvent` and does
  not notice when Erlang's pipe connections close — SIGTERM triggers its
  cleanup handler, which sets `running = 0` and causes `XNextEvent` to
  return on the next interrupt. Errors from an already-closed port are
  silently swallowed.
  """
  def stop_window_pinner(nil), do: :ok

  def stop_window_pinner(port) when is_port(port) do
    try do
      # Capture the OS PID before closing — Port.info returns nil afterward.
      os_pid =
        case Port.info(port) do
          nil -> nil
          info -> Keyword.get(info, :os_pid)
        end

      Port.close(port)

      # Port.close closes Erlang's pipe connections but does not kill the OS
      # process. window_pinner blocks on XNextEvent and won't notice closed
      # pipes, so we send SIGTERM explicitly to trigger its cleanup handler.
      if is_integer(os_pid) do
        System.cmd("kill", ["-TERM", Integer.to_string(os_pid)], stderr_to_stdout: true)
      end

      Mix.shell().info("  window_pinner stopped")
    catch
      :error, :badarg -> :ok
    end

    :ok
  end
end
