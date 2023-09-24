defmodule QuillEx.App do
  @moduledoc """
  QuillEx is a simple text-editor, written in Elixir.
  """

  def start(_type, _args) do
    # QuillEx.Metrics.Instrumenter.setup()

    init_radix_state = QuillEx.Fluxus.Structs.RadixState.new()

    # NOTE: The starting order here is important - we have to start the Registry first.
    children = [
      # QuillEx.Metrics.Stash,
      {Registry, keys: :duplicate, name: QuillEx.PubSub},
      {QuillEx.Fluxus.RadixStore, init_radix_state},
      {Scenic, [scenic_config(init_radix_state)]},
      QuillEx.Fluxus.ActionListener,
      QuillEx.Fluxus.UserInputListener
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  @default_resolution {1680, 1005}
  def scenic_config(radix_state) do
    [
      name: :main_viewport,
      size: @default_resolution,
      default_scene: {QuillEx.Scene.RootScene, radix_state},
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
  end
end
