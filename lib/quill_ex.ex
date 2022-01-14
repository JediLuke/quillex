defmodule QuillEx do
  @moduledoc """
  QuillEx is a simple text-editor, written in Elixir.
  """

  # this is the name of our app, declared in `mix.exs` - THIS HAS TO MATCH !
  @mix_app :quill_ex

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
      ]
    ]
  ]

  @doc """
  Re-compile, and re-start.

  This is to shorten the dev-loop - we can shut-down Scenic & restart it
  in one command.
  """
  def re_compil_start do
    IO.puts("\n#{__MODULE__} stopping...")
    Application.stop(@mix_app)

    IO.puts("\n#{__MODULE__} recompiling...")
    IEx.Helpers.recompile()

    IO.puts("\n#{__MODULE__} starting...\n")
    Application.start(@mix_app)
  end

  @doc """
  Publish an action to the internal event-bus.
  """
  def action(a) do
    # https://www.etatvasoft.com/insights/react-design-patterns-and-structures-of-redux-and-flux/
    # `Flux Architecture`: A design pattern that implements a single mediator
    # (either a reducer or store, depending on implementation) for all actions,
    # through which the app state is processed and returned to the view.

    # 1) ACTION: Here 
    # 2) DISPATCHER: We use EventBus. "Receives actions and broadcasts payloads to registered callbacks"
    # 3) STORE: This is the likes of BufferManager, in combination with RadixState. "Containers for application state & logic that have callbacks registered to the dispatcher." - BufferManager gets triggered by what it sees on EventBus, but all it can do is update the global `RadixState` - this will automatically get broadcast out (also on EventBus)
    # 4) VIEW: This is where it is imporant to write components which are pure functions rendered from state
    # 5) ACTION2: UI interaction achieves interaction by calling further actions in turn (often via the API, developing which not only gives us a nice dev experience, it improves the quality of the GUI code)
    EventBus.notify(%EventBus.Model.Event{
      id: UUID.uuid4(),
      topic: :general,
      data: {:action, a}
    })
  end

  # REMINDER: This launches the supervision tree
  def start(_type, _args) do
    # NOTE: The starting order here is important - we have to start the
    #      Registry first.
    children = [
      # The PubSub broker
      {Registry, keys: :duplicate, name: QuillEx.PubSub},
      {Scenic, [@scenic_config]},
      # listens to the event-bus, manages Buffers
      QuillEx.BufferManager,
      # QuillEx.EventListener,        # listens to the event-bus, triggers actions
      # holds the root-state of the application
      QuillEx.RadixAgent

      # QuillEx.StageManager,
      # QuillEx.MainExecutiveProcess,
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
