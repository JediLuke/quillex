defmodule QuillEx.RadixAgent do
    use Agent
    require Logger
    alias QuillEx.Structs.Radix
  

    def start_link(_opts) do
      Agent.start_link(fn -> %Radix{} end, name: __MODULE__)
    end


    def get do
      Agent.get(__MODULE__, & &1)
    end
  

    # def put(state, key, value) do
    #   Agent.update(__MODULE__, &Map.put(&1, key, value))
    # end


    def put(%Radix{} = new) do
      Logger.debug "!! updating the Radix with: #{inspect new}"
      QuillEx.Scene.RootScene.push_radix_state(new)
      Agent.update(__MODULE__, fn _old -> new end)
    end
  end
  