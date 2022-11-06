defmodule QuillEx.App do
  @moduledoc """
  QuillEx is a simple text-editor, written in Elixir.
  """


  @default_resolution {1680, 1005}

  @scenic_config [
    name: :main_viewport,
    size: @default_resolution,
    default_scene: {QuillEx.Scene.RootScene, nil},
    drivers: [
      [
        module: Scenic.Driver.Local,
        window: [
          title: "QuillEx",
          resizeable: true
        ],
        on_close: :stop_system
        # limit_ms: 500
      ]
    ]
  ]


  def start(_type, _args) do

    # QuillEx.Metrics.Instrumenter.setup()

    # NOTE: The starting order here is important - we have to start the Registry first.
    children = [
      # QuillEx.Metrics.Stash,
      {Registry, keys: :duplicate, name: QuillEx.PubSub},
      QuillEx.Fluxus.RadixStore,
      {Scenic, [@scenic_config]},
      QuillEx.EventListener,
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

end
