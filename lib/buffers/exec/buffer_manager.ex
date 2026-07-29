defmodule Quillex.Buffer.BufferManager do
  @moduledoc """
  The buffer-list RadixCache store AND buffer lifecycle manager, one process.

  Owns the list of open buffers and which one is active. Every mutation
  funnels through `publish/1`, which publishes the full
  `%{buffers: [BufRef], active_buf: BufRef | nil}` snapshot on the retained
  `:radix_buffers` Scenic.PubSub source. Buffer processes edge-cast metadata
  changes (dirty flips, renames) here so the published BufRefs stay fresh.

  Lifecycle and list-state live in one process deliberately: opening or
  closing a buffer IS a buffer-list change — splitting them would race two
  processes over one domain.
  """
  use GenServer
  require Logger

  alias Quillex.RadixCache.Sources

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  # ── Selectors (read side — instant ETS, no GenServer call) ──

  @doc "The retained store snapshot: %{buffers: [BufRef], active_buf: BufRef | nil}"
  def get_state, do: Scenic.PubSub.get(Sources.buffers())

  # ── Actions (write side) ──

  def new_buffer, do: new_buffer(%{})

  def new_buffer(b) when is_binary(b) do
    new_buffer(%{name: b})
  end

  def new_buffer(args) do
    # from the users point of view, there is such a thing as a 'new' buffer,
    # but from the system's point of view, it's just opening another buffer & is not special
    GenServer.call(__MODULE__, {:open_buffer, args})
  end

  def open_buffer(args) do
    GenServer.call(__MODULE__, {:open_buffer, args})
  end

  @doc "Activate a buffer by BufRef or 1-based index. Cast — never blocks the GUI."
  def activate_buffer(buf_ref_or_n) do
    GenServer.cast(__MODULE__, {:activate_buffer, buf_ref_or_n})
  end

  @doc """
  Close a buffer: terminate its process, drop it from the list, reactivate a
  neighbour if it was active. The last remaining buffer cannot be closed.
  """
  def close_buffer(%Quillex.Structs.BufState.BufRef{} = buf_ref) do
    GenServer.cast(__MODULE__, {:close_buffer, buf_ref})
  end

  @doc "Edge-cast from Buffer.Process when display metadata (dirty?, name) transitions."
  def update_buffer_meta(uuid, meta) when is_map(meta) do
    GenServer.cast(__MODULE__, {:buffer_meta, uuid, meta})
  end

  def list_buffers do
    GenServer.call(__MODULE__, :list_buffers)
  end

  def get_live_buffer(%{"uuid" => _buf_uuid} = args) do
    GenServer.call(__MODULE__, {:get_live_buffer, args})
  end

  def get_live_buffer(%Quillex.Structs.BufState.BufRef{} = args) do
    GenServer.call(__MODULE__, {:get_live_buffer, args})
  end

  @doc """
  Synchronous heartbeat: returns after all casts queued before this call have
  been processed (GenServer mailbox ordering). Lets tests/spex observe the
  result of a burst of casts deterministically.
  """
  def sync do
    GenServer.call(__MODULE__, :sync)
  end

  # ── GenServer ──

  def init(_init_arg) do
    Scenic.PubSub.register(Sources.buffers())
    state = %{buffers: [], active_buf: nil}
    Scenic.PubSub.publish(Sources.buffers(), snapshot(state))
    {:ok, state}
  end

  def handle_call({:open_buffer, %Quillex.Structs.BufState.BufRef{} = buf_ref}, _from, state) do
    # check we're not trying to open the same buffer twice
    if Enum.any?(state.buffers, & &1.uuid == buf_ref.uuid) do
      # Legacy broadcast retained for consumers not yet on the store (Phase 7 removes)
      Quillex.Utils.PubSub.broadcast(
          topic: :qlx_events,
          msg: {:action, {:activate_buffer, buf_ref}}
        )
      {:reply, {:ok, buf_ref}, publish(%{state | active_buf: buf_ref})}
    else
      raise "Could not find buffer: #{inspect buf_ref}"
    end
  end

  def handle_call({:open_buffer, args}, _from, state) do
    do_start_new_buffer_process(state, args)
  end

  def handle_call({:get_live_buffer, %{"uuid" => buf_uuid}}, _from, state) do
    case Enum.filter(state.buffers, & &1.uuid == buf_uuid) do
      [] ->
        {:reply, {:error, "buf with uuid: #{inspect buf_uuid} not live"}, state}

      [buf_ref] ->
        {:ok, buf} = Quillex.Buffer.Process.fetch_buf(buf_ref)
        {:reply, {:ok, buf}, state}
    end
  end

  def handle_call({:get_live_buffer,  %Quillex.Structs.BufState.BufRef{uuid: buf_uuid}}, _from, state) do
    case Enum.filter(state.buffers, & &1.uuid == buf_uuid) do
      [] ->
        {:reply, {:error, "buf with uuid: #{inspect buf_uuid} not live"}, state}

      [buf_ref] ->
        {:ok, buf} = Quillex.Buffer.Process.fetch_buf(buf_ref)
        {:reply, {:ok, buf}, state}
    end
  end

  def handle_call(:list_buffers, _from, state) do
    {:reply, state.buffers, state}
  end

  def handle_call(:sync, _from, state) do
    {:reply, :ok, state}
  end

  def handle_cast({:activate_buffer, x}, state) do
    case activate_state(state, x) do
      {:ok, new_state} ->
        {:noreply, publish(new_state)}

      :not_found ->
        Logger.warning("activate_buffer: #{inspect(x)} not found, ignoring")
        {:noreply, state}
    end
  end

  def handle_cast({:close_buffer, %Quillex.Structs.BufState.BufRef{} = buf_ref}, state) do
    case close_state(state, buf_ref) do
      {:ok, new_state} ->
        terminate_buffer_process(buf_ref)
        {:noreply, publish(new_state)}

      :last_buffer ->
        Logger.warning("Cannot close the last buffer")
        {:noreply, state}

      :not_found ->
        Logger.warning("close_buffer: buffer UUID #{buf_ref.uuid} not found, ignoring")
        {:noreply, state}
    end
  end

  def handle_cast({:buffer_meta, uuid, meta}, state) do
    merge = fn
      %Quillex.Structs.BufState.BufRef{uuid: ^uuid} = ref -> struct(ref, meta)
      ref -> ref
    end

    new_state = %{
      state
      | buffers: Enum.map(state.buffers, merge),
        active_buf: state.active_buf && merge.(state.active_buf)
    }

    {:noreply, publish(new_state)}
  end

  # call the actual buffer process
  def call_buffer(%{uuid: buf_uuid}, msg) do
    Registry.lookup(
      Quillex.BufferRegistry,
      {buf_uuid, Quillex.Buffer.Process}
    )
    |> case do
      [{pid, _meta}] ->
        GenServer.call(pid, msg)

      [] ->
        raise "Could not find Buffer.Process process, uuid: #{inspect(buf_uuid)}"
    end
  end

  # ── Pure state transitions (public so unit tests can pin them directly) ──

  @doc false
  def activate_state(state, n) when is_integer(n) and n >= 1 do
    case Enum.at(state.buffers, n - 1) do
      nil -> :not_found
      %Quillex.Structs.BufState.BufRef{} = buf_ref -> activate_state(state, buf_ref)
    end
  end

  def activate_state(state, %Quillex.Structs.BufState.BufRef{} = buf_ref) do
    case Enum.find(state.buffers, &(&1.uuid == buf_ref.uuid)) do
      nil -> :not_found
      %Quillex.Structs.BufState.BufRef{} = found -> {:ok, %{state | active_buf: found}}
    end
  end

  @doc false
  def close_state(state, %Quillex.Structs.BufState.BufRef{} = buf_ref) do
    cond do
      length(state.buffers) <= 1 ->
        :last_buffer

      not Enum.any?(state.buffers, &(&1.uuid == buf_ref.uuid)) ->
        :not_found

      true ->
        new_buffers = Enum.reject(state.buffers, &(&1.uuid == buf_ref.uuid))

        new_active =
          if state.active_buf && state.active_buf.uuid == buf_ref.uuid do
            List.first(new_buffers)
          else
            state.active_buf
          end

        {:ok, %{state | buffers: new_buffers, active_buf: new_active}}
    end
  end

  # ── Internals ──

  # The single commit point: every state mutation publishes the full snapshot.
  defp publish(state) do
    Scenic.PubSub.publish(Sources.buffers(), snapshot(state))
    state
  end

  defp snapshot(state), do: %{buffers: state.buffers, active_buf: state.active_buf}

  defp terminate_buffer_process(%{uuid: uuid}) do
    case Registry.lookup(Quillex.BufferRegistry, {uuid, Quillex.Buffer.Process}) do
      [{pid, _meta}] -> DynamicSupervisor.terminate_child(Quillex.BufferSupervisor, pid)
      [] -> Logger.warning("close_buffer: no live process for #{inspect(uuid)}")
    end
  end

  defp do_start_new_buffer_process(state, args) do
    # If no name provided, generate a unique name
    args = if Map.get(args, :name) || Map.get(args, "name") do
      args
    else
      Map.put(args, :name, generate_unique_buffer_name(state.buffers))
    end

    case Quillex.BufferSupervisor.start_new_buffer_process(args) do
      {:ok, %Quillex.Structs.BufState.BufRef{} = buf_ref} ->
        # Legacy broadcast retained for consumers not yet on the store (Phase 7 removes)
        Quillex.Utils.PubSub.broadcast(
          topic: :qlx_events,
          msg: {:new_buffer_opened, buf_ref}
        )

        new_state = publish(%{state | buffers: state.buffers ++ [buf_ref], active_buf: buf_ref})
        {:reply, {:ok, buf_ref}, new_state}

      {:error, :file_not_found} ->
        {:reply, {:error, :file_not_found}, state}

      {:error, reason} ->
        Logger.warning("Failed to open buffer: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  # Generate a unique buffer name like "untitled", "untitled-2", "untitled-3", etc.
  defp generate_unique_buffer_name(existing_buffers) do
    existing_names = Enum.map(existing_buffers, & &1.name) |> MapSet.new()

    # Find the first available name
    find_available_name(existing_names, 1)
  end

  defp find_available_name(existing_names, n) do
    candidate = if n == 1, do: "untitled", else: "untitled-#{n}"

    if MapSet.member?(existing_names, candidate) do
      find_available_name(existing_names, n + 1)
    else
      candidate
    end
  end
end
