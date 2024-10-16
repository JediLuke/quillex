defmodule Quillex.GUI.QuillexReducer do
  alias Quillex.GUI.Components.Buffer

  def process(%Scenic.Scene{} = scene, {:insert, text, :at_cursor}) do
    active_buf = active_buf(scene)
    new_buf = Buffer.Reducer.process(active_buf, {:insert, text, :at_cursor})

    # update the scene

    # update the graph

    scene
  end

  # TODO move into utils & combine, DRY
  def active_buf(scene) do
    # TODO when we get tabs, we will have to look up what tab we're in, for now asume always first buffer
    hd(scene.assigns.buffers)
  end

  # def process(
  #       %RadixState{} = rdx,
  #       {:open_buffer, %{filepath: filepath}}
  #     ) do
  #   {:ok, buf_ref} = Quillex.Buffer.open(%{filepath: filepath})

  #   rdx
  #   |> Layer1.set_layout(:full_screen)
  #   |> Layer1.set_active_apps([QlxWrap])
  #   |> QlxWrap.Mutator.add_open_buffer(buf_ref)
  #   |> QlxWrap.Mutator.set_active_buf(buf_ref)
  # end
end
