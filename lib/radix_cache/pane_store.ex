defmodule Quillex.RadixCache.PaneStore do
  @moduledoc """
  The pane store — the control plane for a store-backed text surface.

  Owns the retained `:radix_pane_main` source and presents a STABLE contract
  to the TextField: one source to subscribe, one dispatch target for actions,
  fixed for the widget's whole life. Which buffer the pane displays is a
  backend concern:

  - subscribes to `:radix_buffers` to learn the active buffer
  - on change, does the subscription-switching itself: unsubscribe the old
    buffer's source, hydrate from the new one's retained snapshot, subscribe
    for its pushes — and republishes everything on the pane source
  - forwards `{:action, [...]}` casts to the active buffer's process

  So a buffer switch is invisible to the GUI: the TextField just receives a
  different document on the same source and re-renders. No component
  recreation, no cursor smuggling, no widget lifecycle choreography.

  The pane source never publishes nil — before any buffer exists there is
  simply no retained value yet, which the TextField's hydrate path already
  treats as "render from init params".

  Multiple panes later (splits) = more PaneStore instances with their own
  pane ids; the widget contract doesn't change.
  """
  use GenServer
  require Logger

  alias Quillex.RadixCache.Sources

  @pane :main

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "The pane's Scenic.PubSub source — what a TextField subscribes to."
  def source, do: Sources.pane(@pane)

  # ── GenServer ──

  def init(:ok) do
    Scenic.PubSub.register(Sources.pane(@pane))
    # Subscribe before the buffer tree boots; the first :radix_buffers
    # publish tells us which buffer to follow.
    Scenic.PubSub.subscribe(Sources.buffers())
    {:ok, %{buffer_uuid: nil}}
  end

  # Action dispatch from the TextField — forward to the active buffer's store.
  def handle_cast({:action, actions}, %{buffer_uuid: nil} = state) do
    Logger.warning("PaneStore: dropping #{inspect(actions)} — no active buffer")
    {:noreply, state}
  end

  def handle_cast({:action, actions}, %{buffer_uuid: uuid} = state) do
    GenServer.cast(buffer_via(uuid), {:action, actions})
    {:noreply, state}
  end

  # Buffer-list snapshots: retarget when the active buffer changes.
  def handle_info(
        {{Scenic.PubSub, :data}, {:radix_buffers, %{active_buf: active}, _ts}},
        state
      ) do
    new_uuid = active && active.uuid

    cond do
      new_uuid == state.buffer_uuid ->
        {:noreply, state}

      is_nil(new_uuid) ->
        # Cannot happen while the last-buffer guard holds, but stay honest:
        # stop following the old buffer; the pane retains its last snapshot.
        unsubscribe_buffer(state.buffer_uuid)
        {:noreply, %{state | buffer_uuid: nil}}

      true ->
        unsubscribe_buffer(state.buffer_uuid)

        # Hydrate the pane immediately from the retained snapshot, then
        # subscribe for pushes. Subscribe re-delivers the retained value,
        # so nothing published in between can be missed (republishing the
        # same snapshot twice is an idempotent render).
        case Scenic.PubSub.get(Sources.buffer(new_uuid)) do
          nil -> :ok
          buf -> Scenic.PubSub.publish(Sources.pane(@pane), buf)
        end

        Scenic.PubSub.subscribe(Sources.buffer(new_uuid))
        {:noreply, %{state | buffer_uuid: new_uuid}}
    end
  end

  # The followed buffer's snapshots: republish on the pane source. Snapshots
  # from a source we already switched away from are dropped.
  def handle_info({{Scenic.PubSub, :data}, {source, buf, _ts}}, %{buffer_uuid: uuid} = state) do
    if uuid && source == Sources.buffer(uuid) do
      Scenic.PubSub.publish(Sources.pane(@pane), buf)
    end

    {:noreply, state}
  end

  def handle_info({{Scenic.PubSub, :registered}, _}, state), do: {:noreply, state}
  def handle_info({{Scenic.PubSub, :unregistered}, _}, state), do: {:noreply, state}

  # ── Internals ──

  defp unsubscribe_buffer(nil), do: :ok
  defp unsubscribe_buffer(uuid), do: Scenic.PubSub.unsubscribe(Sources.buffer(uuid))

  defp buffer_via(uuid),
    do: {:via, Registry, {Quillex.BufferRegistry, {uuid, Quillex.Buffer.Process}}}
end
