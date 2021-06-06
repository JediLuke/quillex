defmodule QuillEx do
  @moduledoc """
  Starter application using the Scenic framework.
  """


  @default_resolution {1200, 800}

  @default_scenic_viewport_configuration %{
    name: :main_viewport,
    size: @default_resolution,
    default_scene: {QuillEx.Scene.Default, nil},
    drivers: [
      %{
        module: Scenic.Driver.Glfw,
        name: :glfw,
        opts: [resizeable: false, title: "quill_ex"]
      }
    ]
  } 


  def start(_type, _args) do

    children = [
      {Registry, name: QuillEx.PubSub,
                 keys: :duplicate,
                 partitions: System.schedulers_online()},
      # QuillEx.MainExecutiveProcess,
      {Scenic, viewports: [@default_scenic_viewport_configuration]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
