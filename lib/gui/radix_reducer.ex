defmodule Quillex.GUI.RadixReducer do
  def process(%Scenic.Scene{} = scene, action) do
    IO.puts("IGNORING ACTION #{inspect(action)}")
    scene
  end
end
