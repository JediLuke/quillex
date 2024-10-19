defmodule Quillex.BufferSupervisor do
  use DynamicSupervisor
  require Logger

  #   # TODO check if `id` is unique, we could try to use `name` first but should fail if its taken!
  #   # filename also a good id
  #   # TODO check `id` is unique here!

  def start_new_buffer_process(%{filepath: filepath} = args) when is_binary(filepath) do
    # Check if file exists before attempting to read it
    case File.exists?(filepath) do
      true ->
        case File.read(filepath) do
          {:ok, file_content} ->
            lines = String.split(file_content, "\n")

            buf =
              Quillex.Structs.BufState.new(
                Map.merge(args, %{data: lines, name: filepath, source: %{filepath: filepath}})
              )

            do_start_buffer(buf)

          {:error, reason} ->
            {:error, {:failed_to_read_file, reason}}
        end

      false ->
        {:error, :file_not_found}
    end
  end

  def start_new_buffer_process(args) do
    # TODO this could be better (not validated input) but it's ok for now
    buf = Quillex.Structs.BufState.new(args)
    do_start_buffer(buf)
  end

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def do_start_buffer(%Quillex.Structs.BufState{} = buf) do
    spec = {Quillex.Buffer.Process, buf}

    {:ok, buffer_pid} = DynamicSupervisor.start_child(__MODULE__, spec)

    buf_ref = Quillex.Structs.BufState.BufRef.generate(buf, buffer_pid)

    {:ok, buf_ref}
  end
end
