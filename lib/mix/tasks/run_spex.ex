defmodule Mix.Tasks.RunSpex do
  @shortdoc "Run QuillEx spex integration tests with GLFW Scenic driver"
  @moduledoc """
  Runs the QuillEx spex integration tests with the GLFW Scenic driver.

  This is a convenience wrapper around `mix spex` that ensures the
  `SCENIC_LOCAL_TARGET` environment variable is set to `"glfw"`, which is
  required for the Scenic GUI to open a window and render on a desktop.

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

    # Delegate to mix spex, passing through all CLI arguments unchanged.
    Mix.Task.run("spex", args)
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
end
