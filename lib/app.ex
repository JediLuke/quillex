defmodule QuillEx.App do
  @moduledoc """
  QuillEx is a simple text-editor, written in Elixir, using the Scenic gfx lib.
  """

  @tidewave_port 31337
  @start_tidewave? Mix.env() == :dev and Code.ensure_loaded?(Tidewave) and Code.ensure_loaded?(Bandit)

  def start(_type, _args) do
    # QuillEx.Metrics.Instrumenter.setup()

    children =
      # don't boot the GUI, Flamelex is managing Scenic
      if started_by_flamelex?() do
        [
          {Registry, keys: :duplicate, name: QuillEx.PubSub},
          {Quillex.Buffers.TopSupervisor, []}
        ]
      else
        [
          # QuillEx.Metrics.Stash,
          {Registry, keys: :duplicate, name: QuillEx.PubSub},
          {Quillex.Buffers.TopSupervisor, []},
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
  def scenic_config() do
    # Use test window size if available (wider to prevent text wrapping)
    window_size = case Mix.env() do
      :test -> {2000, 1200}  # Force wider window in test environment
      _ -> Application.get_env(:quillex, :test_window_size, @default_resolution)
    end

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
          on_close: :stop_viewport
          # limit_ms: 500
        ]
      ]
    ]
  end

  def started_by_flamelex? do
    Application.get_env(:quillex, :started_by_flamelex?, false)
  end
end
