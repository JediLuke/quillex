defmodule QuillEx.Radix do
    use Agent
    require Logger
  
    @seed_state %{
        #   menubar: ["Open file"],
          menubar: :inactive,
          tabs: :inactive,
          textbox: :inactive,
          bottom_bar: :inactive
      }

    def start_link(_opts) do
      Process.register(self(), __MODULE__)
      Agent.start_link(fn -> @seed_state end)
    end

    def get do
      Agent.get(__MODULE__, & &1) # just return all the state
    end
  

    # def put(state, key, value) do
    #   Agent.update(__MODULE__, &Map.put(&1, key, value))
    # end

    def put(new) do
      Logger.debug "!! updating the Radix with: #{inspect new}"
      Agent.update(__MODULE__, fn -> new end)
    end
  end
  