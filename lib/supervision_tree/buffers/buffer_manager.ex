defmodule Quillex.Buffer.BufferManager do
  use GenServer
  require Logger

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def new_buffer, do: new_buffer(%{})

  def new_buffer(args) do
    # from the users point of view, there is such a thing as a 'new' buffer,
    # but from the system's point of view, it's just opening another buffer & is not special
    GenServer.call(__MODULE__, {:open_buffer, args})
  end

  def open_buffer(args) do
    GenServer.call(__MODULE__, {:open_buffer, args})
  end

  def list_buffers do
    GenServer.call(__MODULE__, :list_buffers)
  end

  def init(_init_arg) do
    {:ok, %{buffers: []}}
  end

  def handle_call({:open_buffer, args}, _from, state) do
    # TODO check we're not trying to open the same buffer twice
    case Quillex.BufferSupervisor.start_new_buffer_process(args) do
      {:ok, %Quillex.Structs.BufState.BufRef{} = buf_ref} ->
        new_state = %{state|buffers: state.buffers ++ [buf_ref]}
        {:reply, {:ok, buf_ref}, new_state}

      {:error, :file_not_found} ->
        {:reply, {:error, :file_not_found}, state}

      {:error, reason} ->
        # raise "in practice this can never happen since `start_new_buffer_process` always returns `{:ok, buf_ref}`"
        Logger.warn("Failed to open buffer: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:list_buffers, _from, state) do
    {:reply, state.buffers, state}
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
        raise "Could not find Buffer process, uuid: #{inspect(buf_uuid)}"
    end
  end

  # similar to the above only instead of sending to the Buffer process,
  # this sends it to the Buffer GUI component process (the Scenic component)
  def cast_to_gui_component(%{uuid: buf_uuid}, msg) do
    Registry.lookup(
      Quillex.BufferRegistry,
      {buf_uuid, Quillex.GUI.Components.BufferPane}
    )
    |> case do
      [{pid, _meta}] ->
        GenServer.cast(pid, msg)

      [] ->
        raise "Could not find Buffer process, uuid: #{inspect(buf_uuid)}"
    end
  end
end


  # # this encapsulates the logic of sending messages to buffers,
  # # so that we're not just casting direct to specific (potentially stale) pid references
  # def cast_to_buffer(%{uuid: buf_uuid}, msg) do
  #   # TODO consider using the process lookup here incase pids have gone stale, but so far, seems to be working...
  #   # TODO maybe this is fine maybe needs to be more robust (do a lookup on name dont use pid)
  #   # this is an example of what I was doing before
  #   # GenServer.cast(buf.pid, {:user_input_fwd, input})
  #   # IO.puts("doing the cast... to #{inspect(buf_ref)}")
  #   # send(buf_ref.pid, msg)

  #   # note that this is cast to buffer but we _send_ to the buffer gui,
  #   # to that the API is a bit different to prevent confusion
  #   Registry.lookup(
  #     Quillex.BufferRegistry,
  #     {buf_uuid, Quillex.Buffer.Process}
  #   )
  #   |> case do
  #     [{pid, _meta}] ->
  #       GenServer.cast(pid, msg)

  #     _else ->
  #       raise "Could not find Buffer process, uuid: #{inspect(buf_uuid)}"
  #   end
  # end
