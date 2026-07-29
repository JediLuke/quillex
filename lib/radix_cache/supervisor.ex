defmodule Quillex.RadixCache.Supervisor do
  @moduledoc """
  RadixCache — the persistent frontend state tree (merlinex pattern).

  Boots with the app, survives all component lifecycle. Organized by data
  domain (buffers, view), NOT by UI layout. Components read from RadixCache
  stores via Scenic.PubSub (ETS-backed, O(1) reads) and subscribe for pushes.

  Store buses:
  - `Scenic.PubSub` — stores → components: retained snapshots, instant `get/1`
  - `Quillex.Utils.PubSub` (Registry) — inbound events → stores

  If data isn't loaded yet, stores publish nil and components render loading
  states. The GUI thread never blocks.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(_opts) do
    # Start Scenic.PubSub here so RadixCache stores can register before Scenic
    # boots. The scenic fork's Scenic.init skips its own start when one is
    # already running.
    ensure_scenic_pubsub()

    # Buffer state is published by Quillex.Buffer.Process / BufferManager,
    # which live under the Buffers supervision tree.
    children = [
      {Quillex.RadixCache.ViewStore, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp ensure_scenic_pubsub do
    case GenServer.whereis(Scenic.PubSub) do
      nil -> Scenic.PubSub.start_link([])
      _pid -> :ok
    end
  end
end
