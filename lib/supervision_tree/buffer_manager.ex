defmodule QuillEx.BufferManager do
    use GenServer
    require Logger
    alias QuillEx.Handlers.BufferActions


    def start_link(_args) do
        GenServer.start_link(__MODULE__, %{})
    end
    
    def init(_args) do
      Logger.debug "#{__MODULE__} initializing..."
      Process.register(self(), __MODULE__)
      EventBus.subscribe({__MODULE__, ["general"]})
      {:ok, %{}}
    end

    def process({:general = _topic, _id} = event_shadow) do
        radix_state = QuillEx.RadixAgent.get()
        event = EventBus.fetch_event(event_shadow)
        {:ok, %QuillEx.Structs.Radix{} = new_radix} =
                radix_state |> BufferActions.calc_radix_change(event.data)

        if new_radix == radix_state do
            Logger.warn "SAME SAME"
        end

        QuillEx.RadixAgent.put(new_radix) #TODO we could probably check & see if radix_state != new_radix, before *always* doing an update...
        EventBus.mark_as_completed({__MODULE__, event_shadow})
    end


end
