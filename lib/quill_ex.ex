defmodule QuillEx do
  @moduledoc """
  Starter application using the Scenic framework.
  """

  @mix_app :quill_ex # this is the name of our app, declared in `mix.exs` - THIS HAS TO MATCH !

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
    IO.puts "\n#{__MODULE__} stopping..."
    Application.stop(@mix_app)

    IO.puts "\n#{__MODULE__} recompiling..."
    IEx.Helpers.recompile

    IO.puts "\n#{__MODULE__} starting...\n"
    Application.start(@mix_app)
  end


  def start(_type, _args) do

    children = [
      QuillEx.Radix,
      {Registry, keys: :duplicate, name: QuillEx.PubSub},
      QuillEx.StageManager,

      # {Registry, name: QuillEx.PubSub,
      #            keys: :duplicate,
      #            partitions: System.schedulers_online()},
      # QuillEx.MainExecutiveProcess,
      {Scenic, [@scenic_config]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
