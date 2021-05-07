defmodule QuillEx do
  @moduledoc """
  Starter application using the Scenic framework.
  """


  @default_resolution {1200, 800}

  @default_conf %{
    name: :main_viewport,
    size: @default_resolution,
    default_scene: {QuillEx.Scene.Home, nil},
    drivers: [
      %{
        module: Scenic.Driver.Glfw,
        name: :glfw,
        opts: [resizeable: false, title: "quill_ex"]
      }
    ]
  } 


  def start(_type, _args) do

    # load the viewport configuration from config
    # start the application with the viewport
    children = [
      {Scenic, viewports: [@default_conf]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
