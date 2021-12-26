defmodule QuillEx.Radix do
    use Agent
    require Logger
  
    @seed_state %{
        #   menubar: ["Open file"],
          # menubar: :inactive,
          # tabs: :inactive,
          # textbox: :inactive,
          # bottom_bar: :inactive
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
      Agent.update(__MODULE__, fn -> new end)
    end
  end
  