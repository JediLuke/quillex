defmodule QuillEx.App do
  @moduledoc """
  QuillEx is a simple text-editor, written in Elixir, using the Scenic gfx lib.
  """

  @tidewave_port 31337
  @start_tidewave? Mix.env() == :dev and Code.ensure_loaded?(Tidewave) and Code.ensure_loaded?(Bandit)

  def start(_type, _args) do

    # Before any child starts: a `qlx` launch runs mix from the project
    # directory, so the VM's cwd is wrong until this puts it right. ViewStore
    # seeds file_nav_path from File.cwd!() in its init — too late to fix after.
    QuillEx.CLI.chdir!()

    children =
      # don't boot the GUI, Flamelex is managing Scenic
      if started_by_flamelex?() do
        [
          # RadixCache starts Scenic.PubSub before buffers register with it
          # (and before Scenic boots — the fork skips its own PubSub start)
          {Quillex.RadixCache.Supervisor, []},
          {Quillex.Buffers.TopSupervisor, []}
        ]
      else
        [
          {Quillex.PerfMonitor, []},
          {Quillex.RadixCache.Supervisor, []},
          {Quillex.Buffers.TopSupervisor, []},
          # opens the `qlx` file argument, if there was one — after the buffer
          # supervisor is up, before RootScene decides it needs a scratch buffer
          {QuillEx.CLI, []},
          {Scenic, [scenic_config()]}
        ]
      end

    children =
      children ++
        if @start_tidewave? do
          require Logger
          Logger.info("Starting Tidewave server on port #{@tidewave_port} for development")
          [{Bandit, plug: Tidewave, port: @tidewave_port}]
        else
          []
        end

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  @window_title if Mix.env() == :test, do: "Quillex (test)", else: "Quillex"
  @default_resolution {1680, 1005}

  # Resolved at compile time, deliberately: Mix does not exist inside a release,
  # so asking Mix.env() while the app is booting would crash the packaged app.
  @test_env? Mix.env() == :test

  def scenic_config() do
    window_size = window_size()

    [
      name: :main_viewport,
      size: window_size,
      default_scene: {QuillEx.RootScene, []},
      drivers: [
        # valid options are: [:name, :limit_ms, :layer, :opacity, :debug, :antialias, :calibration, :position, :window, :cursor, :key_map, :on_close]
        [
          name: :scenic_driver,
          module: Scenic.Driver.Local,
          window: [
            title: @window_title,
            resizeable: true
          ],
          debug: true,
          on_close: on_close()
          # limit_ms: 500
        ]
      ]
    ]
  end

  # Closing the window should end a `qlx` invocation — the shell is sitting
  # there waiting for its prompt back. From an iex session it must not: the
  # session outlives the window.
  defp on_close do
    if QuillEx.CLI.launched_from_cli?(), do: :stop_system, else: :stop_viewport
  end

  # Force a wider window under test so text doesn't wrap mid-assertion.
  defp window_size do
    if @test_env? do
      {2000, 1200}
    else
      Application.get_env(:quillex, :test_window_size, @default_resolution)
    end
  end

  def started_by_flamelex? do
    Application.get_env(:quillex, :started_by_flamelex?, false)
  end
end
