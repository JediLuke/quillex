defmodule Quillex.Buffer.BufferManager do
  use GenServer

  # Public API

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  # Server Callbacks

  def init(init_arg) do
    {:ok, %{}}
  end

  # TODO maybe dont even enforce name here?
  def start_new_buffer(%{"name" => name} = args) do
    GenServer.call(__MODULE__, {:new_buffer, args})
  end

  # def cast_to_buffer(%Quillex.Structs.Buffer.BufRef{} = buf_ref, msg) do
  #   GenServer.cast(buf_ref, msg)
  # end

  def handle_call({:new_buffer, args}, _from, state) do
    case start_buffer(args) do
      # case MyApp.BufferSupervisor.start_buffer_server(buf) do
      {:ok, %Quillex.Structs.Buffer.BufRef{} = buf_ref} ->
        {:reply, {:ok, buf_ref}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def start_buffer(args) do
    # TODO check if `id` is unique, we could try to use `name` first but should fail if its taken!
    # filename also a good id
    # TODO check `id` is unque here!

    # # Generate a new buffer
    # # Quillex.Structs.Buffer.BufRef
    # buf_ref = Quillex.Structs.Buffer.BufRef.generate(buf)
    # # new_buffer = generate_buffer()

    # # Update the state with the new buffer
    # new_state = Map.put(state, new_buffer.id, new_buffer)

    # {:reply, new_buffer, new_state}

    buf = QuillEx.Structs.Buffer.new(args)

    # TODO get pid somehow here and pass it to generate buf ref
    {:ok, buffer_pid} = MyApp.BufferSupervisor.start_buffer_server(buf)
    {:ok, Quillex.Structs.Buffer.BufRef.generate(buf, buffer_pid)}
  end
end
