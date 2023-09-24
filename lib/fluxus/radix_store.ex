defmodule QuillEx.Fluxus.RadixStore do
  use GenServer
  require Logger
  alias QuillEx.Fluxus.Structs.RadixState

  # Client API

  def start_link(%RadixState{} = radix_state) do
    GenServer.start_link(__MODULE__, radix_state, name: __MODULE__)
  end

  # def initialize(new_viewport) do
  #   GenServer.cast(__MODULE__, {:initialize, new_viewport})
  # end

  def get do
    Logger.warn("deprecate RadixStore.get")
    GenServer.call(__MODULE__, :get)
  end

  def put(new_radix_state, broadcast \\ true) do
    Logger.warn("deprecate RadixStore.put")
    GenServer.cast(__MODULE__, {:put, new_radix_state, broadcast})
  end

  def update(new_state) do
    Logger.warn("deprecate RadixStore.update")
    GenServer.cast(__MODULE__, {:update, new_state})
  end

  # Server Callbacks

  def init(radix_state) do
    {:ok, radix_state}
  end

  def handle_call({:action, a}, _from, rdx_state) do
    {:ok, new_radix_state} = QuillEx.Fluxus.RadixReducer.process(rdx_state, a)

    QuillEx.Lib.Utils.PubSub.broadcast(
      topic: :radix_state_change,
      msg: {:radix_state_change, new_radix_state}
    )

    # {:reply, {:ok, new_state}, new_state}
    {:reply, :ok, new_radix_state}
  end

  def handle_call({:user_input, ii}, from, state) do
    # TODO can we return multiple actions?? and handle them sequentially???
    # {:action, action} = QuillEx.Fluxus.UserInputHandler.handle(state, ii)
    # handle_call({:action, action}, from, state)
    # QuillEx.Lib.Utils.PubSub.broadcast(
    #   topic: :radix_state_change,
    #   msg: {:radix_state_change, new_radix_state}
    # )

    # # {:reply, {:ok, new_state}, new_state}
    # {:reply, :ok, new_state}

    case QuillEx.Fluxus.UserInputHandler.handle(state, ii) do
      :ignored ->
        {:reply, :ok, state}

      {:action, action} ->
        handle_call({:action, action}, from, state)
        # {:actions, actions} ->
        #   Enum.reduce(actions, state, fn action, state ->
        #     handle_call({:action, action}, from, state)
        #   end)
    end
  end

  # def handle_cast({:initialize, new_viewport}, state) do
  #   new_state = Map.merge(state, %{gui: Map.put(state.gui, :viewport, new_viewport)})
  #   {:noreply, new_state}
  # end

  def handle_cast({:put, new_radix_state, true}, _state) do
    QuillEx.Lib.Utils.PubSub.broadcast(
      topic: :radix_state_change,
      msg: {:radix_state_change, new_radix_state}
    )

    {:noreply, new_radix_state}
  end

  def handle_cast({:put, new_radix_state, false}, _state) do
    {:noreply, new_radix_state}
  end

  def handle_cast({:update, new_state}, _state) do
    QuillEx.Lib.Utils.PubSub.broadcast(
      topic: :radix_state_change,
      msg: {:radix_state_change, new_state}
    )

    {:noreply, new_state}
  end

  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end
end

# defmodule QuillEx.Fluxus.RadixStore do
#   # TODO make this a GenServer anyway
#   use Agent
#   require Logger
#   alias QuillEx.Fluxus.Structs.RadixState

#   def start_link(%RadixState{} = radix_state) do
#     # new_radix_state = QuillEx.Fluxus.Structs.RadixState.new()
#     Agent.start_link(fn -> radix_state end, name: __MODULE__)
#   end

#   def initialize(viewport: new_viewport) do
#     Agent.update(__MODULE__, fn old ->
#       old |> Map.merge(%{gui: old.gui |> Map.put(:viewport, new_viewport)})
#     end)
#   end

#   def get do
#     Agent.get(__MODULE__, & &1)
#   end

#   # TODO this should be a GenServer so we dont copy the state out & manipulate it in another process

#   # def put(state, key, value) do
#   #   Agent.update(__MODULE__, &Map.put(&1, key, value))
#   # end

#   def put(new_radix_state) do
#     # Logger.debug("!! updating the Radix with: #{inspect(new_radix_state)}")
#     # NOTE: Although I did try it, I decided not to go with using the
#     #      event bus for updating the GUI due to a state change. The event-
#     #      bus serves it's purpose for funneling all action through one
#     #      choke-point, and keeps track of them etc, but just pushing
#     #      updates to the GUI is simpler when done via a PubSub (no need to acknowledge
#     #      events as complete), and easier to implement, since the EventBus
#     #      lib we're using receives events in a separate process to the
#     #      one where we actually declared the function. We could forward
#     #      the state updates on to each ScenicComponent, but then we
#     #      start to have problems of how to handle addressing... the
#     #      exact problem that PubSub is a perfect solution for.
#     QuillEx.Lib.Utils.PubSub.broadcast(
#       topic: :radix_state_change,
#       msg: {:radix_state_change, new_radix_state}
#     )

#     Agent.update(__MODULE__, fn _old -> new_radix_state end)
#   end

#   def put(new_radix_state, :without_broadcast) do
#     Agent.update(__MODULE__, fn _old -> new_radix_state end)
#   end

#   def update(new_state) do
#     # Logger.debug("#{RadixStore} updating state & broadcasting new_state...")
#     # Logger.debug("#{RadixStore} updating state & broadcasting new_state: #{inspect(new_state)}")

#     QuillEx.Lib.Utils.PubSub.broadcast(
#       topic: :radix_state_change,
#       msg: {:radix_state_change, new_state}
#     )

#     Agent.update(__MODULE__, fn _old -> new_state end)
#   end
# end
