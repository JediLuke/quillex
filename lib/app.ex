defmodule Quillex.App do
  @moduledoc """
  Quillex is a simple text-editor, written in Elixir, using the Scenic gfx lib.
  """

  @tidewave_port 31337
  @start_tidewave? Mix.env() == :dev and Code.ensure_loaded?(Tidewave) and
                     Code.ensure_loaded?(Bandit)

  def start(_type, _args) do
    mode = runtime_mode()

    # Working-directory adoption is standalone shell policy. Embedded and
    # headless hosts retain ownership of their process-wide current directory.
    if mode == :standalone, do: Quillex.CLI.chdir!()

    children = children_for(mode)

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

  @doc "Return the generic Quillex runtime mode."
  @spec runtime_mode() :: :standalone | :embedded | :headless
  def runtime_mode do
    case Application.get_env(:quillex, :runtime_mode, :standalone) do
      mode when mode in [:standalone, :embedded, :headless] -> mode
      mode -> raise ArgumentError, "invalid Quillex runtime mode: #{inspect(mode)}"
    end
  end

  @doc false
  def children_for(:standalone) do
    [
      {Quillex.PerfMonitor, []},
      {Quillex.RadixCache.Supervisor, []},
      {Quillex.Buffers.TopSupervisor, []},
      {Quillex.Lifecycle.Coordinator, []},
      {Quillex.CLI, []},
      {Scenic, [scenic_config()]}
    ]
  end

  def children_for(:embedded) do
    [
      {Quillex.RadixCache.Supervisor, []},
      {Quillex.Buffers.TopSupervisor, []}
    ]
  end

  def children_for(:headless) do
    [
      {Quillex.RadixCache.Supervisor, []},
      {Quillex.Buffers.TopSupervisor, []}
    ]
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
      default_scene: {Quillex.RootScene, []},
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
          on_close: {__MODULE__, :request_close, []}
          # limit_ms: 500
        ]
      ]
    ]
  end

  @doc false
  def request_close(reason) do
    Quillex.Lifecycle.Coordinator.request_close(reason)
    :defer
  end

  # Force a wider window under test so text doesn't wrap mid-assertion.
  defp window_size do
    if @test_env? do
      {2000, 1200}
    else
      Application.get_env(:quillex, :test_window_size, @default_resolution)
    end
  end
end
