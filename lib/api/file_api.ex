defmodule Quillex.API.FileAPI do
  @moduledoc """
  File operations API for Quillex text editor.
  
  Provides a clean interface for opening, saving, and manipulating files
  in the text editor through IEx or other programmatic interfaces.
  
  ## Examples
  
      # Open a file
      iex> Quillex.API.FileAPI.open("test/support/spinozas_ethics_p1.txt")
      {:ok, %{buffer_ref: ..., file_path: "test/support/spinozas_ethics_p1.txt"}}
      
      # Save current buffer 
      iex> Quillex.API.FileAPI.save()
      {:ok, %{file_path: "test/support/spinozas_ethics_p1.txt", bytes_written: 12345}}
      
      # Save as new file
      iex> Quillex.API.FileAPI.save_as("my_notes.txt")
      {:ok, %{file_path: "my_notes.txt", bytes_written: 567}}
  """

  alias Quillex.Buffer

  @doc """
  Opens a file in the text editor.
  
  Creates a new buffer with the file contents and switches to it.
  If the file doesn't exist, creates a new empty buffer associated with that path.
  
  ## Parameters
  - `file_path` - Path to the file to open (string)
  
  ## Returns
  - `{:ok, %{buffer_ref: ref, file_path: path}}` on success
  - `{:error, reason}` on failure
  """
  def open(file_path) when is_binary(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        # File exists, create buffer with content
        {:ok, buf_ref} = Buffer.new(%{
          file_path: file_path,
          data: String.split(content, "\n"),
          dirty: false
        })
        
        # Switch to the new buffer
        Buffer.switch(buf_ref)
        
        {:ok, %{
          buffer_ref: buf_ref,
          file_path: file_path,
          lines: length(String.split(content, "\n")),
          bytes: byte_size(content)
        }}
        
      {:error, :enoent} ->
        # File doesn't exist, create new buffer for this path
        {:ok, buf_ref} = Buffer.new(%{
          file_path: file_path,
          data: [""],
          dirty: false
        })
        
        # Switch to the new buffer
        Buffer.switch(buf_ref)
        
        {:ok, %{
          buffer_ref: buf_ref,
          file_path: file_path,
          lines: 1,
          bytes: 0,
          created: true
        }}
        
      {:error, reason} ->
        {:error, "Failed to open #{file_path}: #{reason}"}
    end
  end

  @doc """
  Saves the current active buffer to its associated file.
  
  If the buffer has no associated file path, returns an error.
  Use `save_as/1` to save to a new file path.
  
  ## Returns
  - `{:ok, %{file_path: path, bytes_written: count}}` on success
  - `{:error, reason}` on failure
  """
  def save() do
    case get_active_buffer_data() do
      {:ok, %{file_path: nil}} ->
        {:error, "No file path associated with current buffer. Use save_as/1 instead."}
        
      {:ok, %{file_path: file_path, data: lines}} ->
        content = Enum.join(lines, "\n")
        
        case File.write(file_path, content) do
          :ok ->
            # Mark buffer as clean (not dirty)
            mark_buffer_clean()
            
            {:ok, %{
              file_path: file_path,
              bytes_written: byte_size(content),
              lines: length(lines)
            }}
            
          {:error, reason} ->
            {:error, "Failed to save #{file_path}: #{reason}"}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Saves the current active buffer to a specific file path.
  
  ## Parameters
  - `file_path` - Path where to save the file (string)
  
  ## Returns
  - `{:ok, %{file_path: path, bytes_written: count}}` on success
  - `{:error, reason}` on failure
  """
  def save_as(file_path) when is_binary(file_path) do
    case get_active_buffer_data() do
      {:ok, %{data: lines}} ->
        content = Enum.join(lines, "\n")
        
        case File.write(file_path, content) do
          :ok ->
            # Update buffer to associate with new file path and mark clean
            update_buffer_file_path(file_path)
            mark_buffer_clean()
            
            {:ok, %{
              file_path: file_path,
              bytes_written: byte_size(content),
              lines: length(lines)
            }}
            
          {:error, reason} ->
            {:error, "Failed to save #{file_path}: #{reason}"}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a new empty buffer.
  
  ## Parameters
  - `opts` - Optional parameters (keyword list)
    - `:name` - Name for the buffer (default: auto-generated)
    - `:file_path` - Associate with a file path (default: nil)
  
  ## Returns
  - `{:ok, %{buffer_ref: ref}}` on success
  - `{:error, reason}` on failure
  """
  def new(opts \\ []) do
    file_path = Keyword.get(opts, :file_path)
    name = Keyword.get(opts, :name)
    
    {:ok, buf_ref} = Buffer.new(%{
      file_path: file_path,
      name: name,
      data: [""],
      dirty: false
    })
    
    # Switch to the new buffer
    Buffer.switch(buf_ref)
    
    {:ok, %{buffer_ref: buf_ref}}
  end

  @doc """
  Gets information about the current active buffer.
  
  ## Returns
  - `{:ok, %{file_path: path, lines: count, dirty: boolean, buffer_ref: ref}}` on success
  - `{:error, reason}` on failure
  """
  def info() do
    case get_active_buffer_data() do
      {:ok, data} ->
        {:ok, %{
          file_path: data.file_path,
          lines: length(data.data),
          dirty: Map.get(data, :dirty, false),
          buffer_ref: Map.get(data, :buffer_ref),
          bytes: data.data |> Enum.join("\n") |> byte_size()
        }}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all open buffers.
  
  ## Returns
  - List of buffer information maps
  """
  def list_buffers() do
    Buffer.list()
    |> Enum.map(fn buf_info ->
      %{
        buffer_ref: buf_info.ref,
        file_path: Map.get(buf_info, :file_path),
        dirty: Map.get(buf_info, :dirty, false),
        lines: case Map.get(buf_info, :data) do
          nil -> 0
          data when is_list(data) -> length(data)
          _ -> 1
        end
      }
    end)
  end

  @doc """
  Switches to a buffer by file path or buffer reference.
  
  ## Parameters
  - `identifier` - File path (string) or buffer reference
  
  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure
  """
  def switch_to(identifier) when is_binary(identifier) do
    # Switch by file path
    case Enum.find(list_buffers(), fn buf -> buf.file_path == identifier end) do
      nil ->
        {:error, "No buffer found for file path: #{identifier}"}
        
      buf ->
        Buffer.switch(buf.buffer_ref)
        :ok
    end
  end
  
  def switch_to(buffer_ref) do
    # Switch by buffer reference
    Buffer.switch(buffer_ref)
    :ok
  end

  # Private helper functions

  defp get_active_buffer_data() do
    try do
      active_buf = Buffer.active_buf()
      {:ok, active_buf}
    rescue
      e ->
        {:error, "Failed to get active buffer: #{inspect(e)}"}
    end
  end

  defp mark_buffer_clean() do
    # TODO: Implement buffer dirty state management
    # This would require extending the buffer state management
    :ok
  end

  defp update_buffer_file_path(_file_path) do
    # TODO: Implement buffer file path updating
    # This would require extending the buffer state management
    :ok
  end
end