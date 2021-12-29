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
      #NOTE: Although I did try it, I decided not to go with using the
      #      event bus for updating the GUI due to a state change. The event-
      #      bus serves it's purpose for funneling all action through one
      #      choke-point, and keeps track of them etc, but just pushing
      #      updates to the GUI is simpler when done via a PubSub (no need to acknowledge
      #      events as complete), and easier to implement, since the EventBus
      #      lib we're using receives events in a separate process to the
      #      one where we actually declared the function. We could forward
      #      the state updates on to each ScenicComponent, but then we
      #      start to have problems of how to handle addressing... the
      #      exact problem that PubSub is a perfect solution for.
      QuillEx.Utils.PubSub.broadcast(topic: :radix_state_change, msg: {:radix_state_change, new})
      Agent.update(__MODULE__, fn _old -> new end)
    end
  end
  