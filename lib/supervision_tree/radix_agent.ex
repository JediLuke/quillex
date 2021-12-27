defmodule QuillEx.RadixAgent do
    use Agent
    require Logger
  
    @seed_state %{
      buffers: []
    }

    def start_link(_opts) do
      Agent.start_link(fn -> @seed_state end, name: __MODULE__)
    end

    # def get do
    #   IO.puts "HERE"
    #   Process.whereis(__MODULE__) |> Agent.get(& &1) # just return all the state
    # end

    def get do
      Agent.get(__MODULE__, & &1)
    end
  

    # def put(state, key, value) do
    #   Agent.update(__MODULE__, &Map.put(&1, key, value))
    # end

    def put(new) do
      Logger.debug "!! updating the Radix with: #{inspect new}"
      QuillEx.Scene.RootScene.push_radix_state(new)
      Agent.update(__MODULE__, fn _old -> new end)
    end
  end
  