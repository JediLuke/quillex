defmodule QuillEx.EventListener do
    use GenServer
    require Logger


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
        # GenServer.cast(self(), {:event, event_shadow})
        fluxus_radix = QuillEx.Radix.get()
        event = EventBus.fetch_event(event_shadow)
        do_process(fluxus_radix, event)
        EventBus.mark_as_completed({__MODULE__, event_shadow})
    end

    def do_process(radix, event) do
        Logger
        IO.puts "YES"
        :ok
    end

    # def handle_cast({:event, {_topic, _id} = event_shadow}, state) do
    #     # version >= 1.4.0
    #     IO.puts "GOT ONE #{inspect event_shadow}"
    #     
    #     IO.inspect event
    #     # EventBus.mark_as_skipped({__MODULE__, event_shadow})
    #     {:noreply, state}
    #   end
end