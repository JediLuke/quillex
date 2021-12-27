defmodule QuillEx.BufferManager do
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
        fluxus_radix = QuillEx.RadixAgent.get()
        event = EventBus.fetch_event(event_shadow)
        :ok = do_process(fluxus_radix, event.data)
        EventBus.mark_as_completed({__MODULE__, event_shadow})
    end

    ##--------------------------------------------------------

    def do_process(%{buffers: buf_list} = radix, {:action, {:open_buffer, new_buf}}) do
        Logger.debug "Opening new buffer..."

        #NOTE: Our goal is to update the Radix state with the new buffer
        #      - that change will send out msgs to the GUI to make updates
        num_buffers = Enum.count(buf_list)
        #TODO make this a struct?
        new_buffer_id = "untitled_" <> Integer.to_string(num_buffers+1) <> ".txt"
        new_buffer_list = buf_list ++ [new_buf |> Map.merge(%{id: new_buffer_id})]
        QuillEx.RadixAgent.put(radix |> Map.put(:buffers, new_buffer_list))
        :ok
    end

end
