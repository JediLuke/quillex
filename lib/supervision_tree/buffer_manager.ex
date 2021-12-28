defmodule QuillEx.BufferManager do
    use GenServer
    require Logger
    alias QuillEx.Structs.Radix
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
        fluxus_radix = QuillEx.RadixAgent.get()
        event = EventBus.fetch_event(event_shadow)
        {:ok, %Radix{} = new_radix} = fluxus_radix |> BufferActions.calc_radix_change(event.data)
        QuillEx.RadixAgent.put(new_radix) #TODO we could probably check & see if fluxus_radix != new_radix, before *always* doing an update...
        EventBus.mark_as_completed({__MODULE__, event_shadow})
    end


end
