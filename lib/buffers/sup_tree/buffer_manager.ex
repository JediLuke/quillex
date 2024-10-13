defmodule Quillex.Buffer.BufferManager do
  use GenServer

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(init_arg) do
    {:ok, %{}}
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

  # this encapsulates the logic of sending messages to buffers,
  # so that we're not just casting direct to specific (potentially stale) pid references
  def cast_to_buffer(%Quillex.Structs.Buffer.BufRef{} = buf_ref, msg) do
    # TODO consider using the process lookup here incase pids have gone stale, but so far, seems to be working...
    # TODO maybe this is fine maybe needs to be more robust (do a lookup on name dont use pid)
    # this is an example of what I was doing before
    # GenServer.cast(buf.pid, {:user_input_fwd, input})

    IO.puts("doing the cast... to #{inspect(buf_ref)}")
    GenServer.cast(buf_ref.pid, msg)
  end

  def handle_call({:open_buffer, args}, _from, state) do
    # TODO check we're not trying to open the same buffer twice
    case Quillex.BufferSupervisor.start_new_buffer_process(args) do
      {:ok, %Quillex.Structs.Buffer.BufRef{} = buf_ref} ->
        {:reply, {:ok, buf_ref}, state}

      {:error, reason} ->
        raise "in practice this can never happen since `start_new_buffer_process` always returns `{:ok, buf_ref}`"
        {:reply, {:error, reason}, state}
    end
  end
end
