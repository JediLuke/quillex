defmodule Quillex.Buffer do
  alias Quillex.Buffer.{Ref, Snapshot}

  @doc """
  Create a new empty buffer with default settings.
  Equivalent to `new(%{})`.
  """
  @spec new() :: {:ok, Ref.t()}
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
  @spec new(map()) :: {:ok, Ref.t()}
  def new(args) when is_map(args) do
    with {:ok, buf_ref} <- Quillex.Buffer.BufferManager.new_buffer(args) do
      {:ok, Ref.from_internal(buf_ref)}
    end
  end

  def new(args) do
    raise ArgumentError, "Quillex.Buffer.new/1 expects a map, got: #{inspect(args)}"
  end

  @doc "Open a buffer by delegating to `BufferManager.open_buffer/1`."
  @spec open(map()) :: {:ok, Ref.t()}
  def open(args) do
    with {:ok, buf_ref} <- Quillex.Buffer.BufferManager.open_buffer(args) do
      {:ok, Ref.from_internal(buf_ref)}
    end
  end

  @doc "List all currently open buffers."
  @spec list() :: list()
  def list do
    Enum.map(Quillex.Buffer.BufferManager.list_buffers(), &Ref.from_internal/1)
  end

  @doc "Return the active buffer reference from the retained buffer-list store."
  @spec active_buf() :: Ref.t() | nil
  def active_buf do
    active()
  end

  def active do
    case Quillex.Buffer.BufferManager.get_state() do
      {:data, %{active_buf: ref}, _meta} -> ref && Ref.from_internal(ref)
      %{active_buf: ref} -> ref && Ref.from_internal(ref)
      _ -> nil
    end
  end

  @doc "Fetch a buffer snapshot by explicit reference."
  def fetch(buf_ref) do
    with {:ok, state} <- Quillex.Buffer.Process.fetch_buf(buf_ref) do
      {:ok, Snapshot.from_internal(state)}
    end
  end

  @doc "Activate an explicit buffer reference."
  def activate(buf_ref) do
    Quillex.Buffer.BufferManager.activate_buffer(buf_ref)
    Quillex.Buffer.BufferManager.sync()
  end

  @doc "Return every dirty buffer reference."
  def dirty_buffers, do: Enum.filter(list(), & &1.dirty?)

  @doc "Close a clean buffer; dirty buffers require explicit discard."
  def close(%{dirty?: true}), do: {:error, :dirty}

  def close(buf_ref) do
    Quillex.Buffer.BufferManager.close_buffer(buf_ref)
  end

  def close(buf_ref, :discard) do
    Quillex.Buffer.BufferManager.close_buffer(buf_ref)
  end

  @doc "Persist an explicit file-backed buffer. Disk I/O stays outside the reducer."
  def save(buf_ref) do
    with {:ok, snapshot} <- fetch(buf_ref),
         path when is_binary(path) <- snapshot.ref.path,
         content = Enum.join(snapshot.lines, "\n"),
         :ok <- File.write(path, content),
         {:ok, updated} <- dispatch(buf_ref, :mark_clean) do
      {:ok, updated}
    else
      nil -> {:error, :no_path}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :no_path}
    end
  end

  @doc "Persist an explicit buffer under a canonical path."
  def save_as(buf_ref, path) when is_binary(path) do
    path = Quillex.Buffer.PathIdentity.canonical(path)

    case Enum.find(list(), &(&1.path == path and &1.uuid != buf_ref.uuid)) do
      nil ->
        with {:ok, snapshot} <- fetch(buf_ref),
             content = Enum.join(snapshot.lines, "\n"),
             :ok <- File.write(path, content),
             {:ok, updated} <- dispatch(buf_ref, [{:set_file_path, path}, :mark_clean]) do
          {:ok, updated}
        end

      _existing ->
        {:error, :path_already_open}
    end
  end

  @doc "Reload a file-backed buffer from disk without performing I/O in the reducer."
  def reload(buf_ref) do
    with {:ok, snapshot} <- fetch(buf_ref),
         path when is_binary(path) <- snapshot.ref.path,
         {:ok, content} <- File.read(path),
         lines = String.split(content, "\n"),
         {:ok, updated} <- dispatch(buf_ref, [{:set_data, lines}, :mark_clean]) do
      {:ok, updated}
    else
      nil -> {:error, :no_path}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :no_path}
    end
  end

  @doc "Dispatch semantic editing actions to an explicit buffer."
  def dispatch(buf_ref, actions) do
    with {:ok, state} <- Quillex.Buffer.BufferManager.call_buffer(buf_ref, {:action, actions}) do
      {:ok, Snapshot.from_internal(state)}
    end
  end

  @doc "Switch to the buffer at position `n` (1-based index) in the open buffer list."
  @spec switch(pos_integer()) :: :ok
  def switch(n) when is_integer(n) do
    activate(n)
  end

  # Switch to the given buffer reference.
  @spec switch(Ref.t()) :: :ok
  def switch(buf_ref) do
    activate(buf_ref)
  end
end
