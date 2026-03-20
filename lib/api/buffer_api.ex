defmodule Quillex.Buffer do

  @doc """
  Create a new empty buffer with default settings.
  Equivalent to `new(%{})`.
  """
  @spec new() :: {:ok, Quillex.Structs.BufState.BufRef.t()}
  def new(), do: new(%{})

  @doc """
  Create a new buffer with the given arguments.

  ## Parameters
  - `args` - Map of buffer options (`:name`, `:data`, `:filepath`, `:dirty`, etc.)

  ## Returns
  - `{:ok, buf_ref}` on success
  - Raises `ArgumentError` when `args` is not a map

  ## Notes
  Creating a buffer triggers a PubSub broadcast. The RootScene will automatically
  receive and activate the new buffer via `{:new_buffer_opened, buf_ref}` — do NOT
  call `Buffer.switch/1` afterwards as that can race with the PubSub message.
  """
  @spec new(map()) :: {:ok, Quillex.Structs.BufState.BufRef.t()}
  def new(args) when is_map(args) do
    {:ok, _buf_ref} = Quillex.Buffer.BufferManager.new_buffer(args)
    # switch(buf_ref)
  end

  def new(args) do
    raise ArgumentError, "Quillex.Buffer.new/1 expects a map, got: #{inspect(args)}"
  end

  @doc "Open a buffer by delegating to `BufferManager.open_buffer/1`."
  @spec open(map()) :: {:ok, Quillex.Structs.BufState.BufRef.t()}
  defdelegate open(args), to: Quillex.Buffer.BufferManager, as: :open_buffer

  @doc "List all currently open buffers."
  @spec list() :: list()
  defdelegate list(), to: Quillex.Buffer.BufferManager, as: :list_buffers

  @doc "Return the active buffer reference from the RootScene."
  @spec active_buf() :: Quillex.Structs.BufState.BufRef.t() | nil
  def active_buf do
    {:ok, active_buf} = GenServer.call(QuillEx.RootScene, :get_active_buffer)
    active_buf
  end

  @doc "Switch to the buffer at position `n` (1-based index) in the open buffer list."
  @spec switch(pos_integer()) :: :ok
  def switch(n) when is_integer(n) do
    GenServer.cast(QuillEx.RootScene, {:action, {:activate_buffer, n}})
  end

  @doc "Switch to the given buffer reference."
  @spec switch(Quillex.Structs.BufState.BufRef.t()) :: :ok
  def switch(buf_ref) do
    GenServer.cast(QuillEx.RootScene, {:action, {:activate_buffer, buf_ref}})
  end

end
