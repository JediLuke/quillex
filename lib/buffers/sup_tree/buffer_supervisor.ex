defmodule Quillex.BufferSupervisor do
  use DynamicSupervisor
  require Logger

  # def start_buffer(args) do

  #   # # Generate a new buffer
  #   # # Quillex.Structs.Buffer.BufRef
  #   # buf_ref = Quillex.Structs.Buffer.BufRef.generate(buf)
  #   # # new_buffer = generate_buffer()

  #   # # Update the state with the new buffer
  #   # new_state = Map.put(state, new_buffer.id, new_buffer)

  #   # {:reply, new_buffer, new_state}

  #   buf = Quillex.Structs.Buffer.new(args)

  #   # TODO get pid somehow here and pass it to generate buf ref
  #   {:ok, buffer_pid} = Quillex.BufferSupervisor.start_buffer(buf)
  #   {:ok, Quillex.Structs.Buffer.BufRef.generate(buf, buffer_pid)}
  # end

  #   # TODO check if `id` is unique, we could try to use `name` first but should fail if its taken!
  #   # filename also a good id
  #   # TODO check `id` is unque here!

  def start_new_buffer_process(%{filepath: filepath}) when is_binary(filepath) do
    {:ok, file_content} = File.read(filepath)
    lines = String.split(file_content, "\n")
    buf = Quillex.Structs.Buffer.new(%{data: lines, source: %{filepath: filepath}})

    do_start_buffer(buf)
  end

  def start_new_buffer_process(args) do
    # TODO this could be better but it's ok for now
    # Logger.warning(
    #   "Should be valiodating better, starting buf process with args: #{inspect(args)}"
    # )

    buf = Quillex.Structs.Buffer.new(args)
    # spec = {Quillex.Buffer.Process, buf}
    # {:ok, buffer_pid} = DynamicSupervisor.start_child(__MODULE__, spec)
    # buf_ref = Quillex.Structs.Buffer.BufRef.generate(buf, buffer_pid)

    # {:ok, buf_ref}

    do_start_buffer(buf)
  end

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def do_start_buffer(%Quillex.Structs.Buffer{} = buf) do
    # {:ok, buffer_pid} = Quillex.Buffer.Process.start_link(buf)
    # {:ok, Quillex.Structs.Buffer.BufRef.generate(buf, buffer_pid)}

    spec = {Quillex.Buffer.Process, buf}
    {:ok, buffer_pid} = DynamicSupervisor.start_child(__MODULE__, spec)
    buf_ref = Quillex.Structs.Buffer.BufRef.generate(buf, buffer_pid)

    {:ok, buf_ref}
  end
end
