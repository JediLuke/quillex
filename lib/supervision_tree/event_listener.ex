defmodule QuillEx.EventListener do
  use GenServer
  require Logger

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(_args) do
    Logger.debug("#{__MODULE__} initializing...")
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

  ## --------------------------------------------------------

  def do_process(radix_state, action) do
    Logger.debug(
      "#{__MODULE__} ignoring... #{inspect(%{radix_state: radix_state, action: action})}"
    )

    :ok
  end
end
