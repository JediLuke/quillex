defmodule QuillEx.App do
  @moduledoc """
  QuillEx is a simple text-editor, written in Elixir, using the Scenic gfx lib.
  """

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
        # Conditionally start Tidewave server for development
        if Mix.env() == :dev and Code.ensure_loaded?(Tidewave) and Code.ensure_loaded?(Bandit) do
          require Logger
          Logger.info("Starting Tidewave server on port 4000 for development")
          [{Bandit, plug: Tidewave, port: 4000}]
        else
          []
        end

    children = Supervisor.start_link(children, strategy: :one_for_one)
  end

  @window_title "Quillex"
  @default_resolution {1680, 1005}
  def scenic_config() do
    [
      name: :main_viewport,
      size: @default_resolution,
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
          on_close: :stop_system
          # limit_ms: 500
        ]
      ]
    ]
  end

  def started_by_flamelex? do
    Application.get_env(:quillex, :started_by_flamelex?, false)
  end
end
