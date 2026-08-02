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

      # Verify file integrity (check if file changed on disk)
      iex> Quillex.API.FileAPI.verify_file_integrity()
      {:ok, :unchanged}
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
    # Opening an already-open file ACTIVATES its existing buffer instead of
    # duplicating it. (Duplicates also produce identical tab labels, which
    # breaks anything addressing tabs by name — found via a Tab Navigation
    # spex flake where "app.ex" appeared twice in the tab bar.)
    existing =
      Quillex.Buffer.BufferManager.list_buffers()
      |> Enum.find(fn b -> match?(%{source: %{filepath: ^file_path}}, b) end)

    if existing do
      buf_ref = struct(Quillex.Structs.BufState.BufRef, uuid: existing.uuid, name: existing.name)
      :ok = Quillex.Buffer.switch(buf_ref)

      {:ok,
       %{
         buffer_ref: buf_ref,
         file_path: file_path,
         lines: length(existing.data),
         bytes: existing.data |> Enum.join("\n") |> byte_size()
       }}
    else
      do_open_new(file_path)
    end
  end

  defp do_open_new(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        # File exists, create buffer with content.
        # Buffer.new/1 triggers BufferManager which broadcasts {:new_buffer_opened, buf_ref}
        # via PubSub. RootScene.handle_info/2 adds AND activates the buffer automatically.
        # Do NOT call Buffer.switch/1 here — it would send a redundant {:activate_buffer}
        # cast that may arrive before the PubSub message, causing RootScene to raise
        # "Buffer not found" because the buffer has not yet been added to state.
        {:ok, buf_ref} = Buffer.new(%{
          name: Path.basename(file_path),
          source: %{filepath: file_path},
          data: String.split(content, "\n"),
          dirty: false
        })

        {:ok, %{
          buffer_ref: buf_ref,
          file_path: file_path,
          lines: length(String.split(content, "\n")),
          bytes: byte_size(content)
        }}

      {:error, :enoent} ->
        # File doesn't exist, create new buffer for this path.
        # Same reasoning as above — PubSub handles activation; no explicit switch needed.
        {:ok, buf_ref} = Buffer.new(%{
          name: Path.basename(file_path),
          source: %{filepath: file_path},
          data: [""],
          dirty: false
        })

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

    # Buffer.new/1 triggers PubSub {:new_buffer_opened, buf_ref}; RootScene activates it.
    # Do NOT call Buffer.switch/1 — the PubSub message already handles activation and the
    # explicit switch cast can race with the PubSub message, crashing RootScene.
    {:ok, buf_ref} = Buffer.new(%{
      source: if(file_path, do: %{filepath: file_path}, else: nil),
      name: name,
      data: [""],
      dirty: false
    })

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
        buffer_ref: buf_info,
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
  Reloads the current active buffer's content from disk.

  Reads the file associated with the active buffer and replaces the buffer's
  in-memory content with the file's current content on disk. Resets the cursor
  to the start of the document and marks the buffer as clean (not dirty).

  This is the complement to `verify_file_integrity/0`: once verification reports
  that the file has been modified on disk, `reload/0` fetches the new version.

  ## Returns
  - `{:ok, %{file_path: path, lines: count, bytes: count}}` on success
  - `{:error, reason}` on failure (no file path, file deleted, I/O error)
  """
  def reload() do
    case get_active_buffer_data() do
      {:ok, %{file_path: nil}} ->
        {:error, "Buffer has no associated file path"}

      {:ok, %{file_path: file_path, buffer_ref: buf_ref}} ->
        case File.read(file_path) do
          {:ok, content} ->
            new_lines = String.split(content, "\n")
            # Send three actions as a list so the buffer process applies them atomically:
            #   {:set_data, lines}    — replace buffer content
            #   {:set_cursor, {1,1}}  — reset cursor to start of document
            #   :mark_clean           — clear dirty flag (reload from disk is not a user edit)
            Quillex.Buffer.BufferManager.call_buffer(
              buf_ref,
              {:action, [{:set_data, new_lines}, {:set_cursor, {1, 1}}, :mark_clean]}
            )

            {:ok, %{
              file_path: file_path,
              lines: length(new_lines),
              bytes: byte_size(content)
            }}

          {:error, :enoent} ->
            {:error, "File has been deleted from disk"}

          {:error, reason} ->
            {:error, "Failed to read #{file_path}: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Verifies if the current buffer's file has been modified on disk.

  Compares the current buffer content with the file on disk to detect
  external modifications. This is useful for detecting when another
  program has modified the file.

  ## Returns
  - `{:ok, :unchanged}` - File matches buffer content
  - `{:ok, :modified}` - File has been modified on disk
  - `{:ok, :deleted}` - File has been deleted from disk
  - `{:ok, :no_file}` - Buffer has no associated file path
  - `{:error, reason}` - Error reading file or buffer
  """
  def verify_file_integrity() do
    case get_active_buffer_data() do
      {:ok, %{file_path: nil}} ->
        {:ok, :no_file}

      {:ok, %{file_path: file_path, data: buffer_lines}} ->
        check_file_status(buffer_lines, file_path)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Compares a list of buffer lines against a file on disk.

  This is the pure comparison function underlying `verify_file_integrity/0`.
  It can be called directly with known data for testing or programmatic use.

  ## Parameters
  - `buffer_lines` - List of strings representing the buffer content
  - `file_path` - Path to the file on disk

  ## Returns
  - `{:ok, :unchanged}` - File content matches `buffer_lines`
  - `{:ok, :modified}` - File content differs from `buffer_lines`
  - `{:ok, :deleted}` - File does not exist on disk
  - `{:error, reason}` - Read error (permissions, I/O failure, etc.)
  """
  def check_file_status(buffer_lines, file_path)
      when is_list(buffer_lines) and is_binary(file_path) do
    case File.read(file_path) do
      {:ok, disk_content} ->
        disk_lines = String.split(disk_content, "\n")

        if buffer_lines == disk_lines do
          {:ok, :unchanged}
        else
          {:ok, :modified}
        end

      {:error, :enoent} ->
        {:ok, :deleted}

      {:error, reason} ->
        {:error, "Failed to read #{file_path}: #{reason}"}
    end
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
      buf_ref = Buffer.active_buf()

      case buf_ref do
        nil ->
          {:error, "No active buffer"}

        buf_ref ->
          case Quillex.Buffer.Process.fetch_buf(buf_ref) do
            {:ok, %Quillex.Structs.BufState{} = buf_state} ->
              file_path = case buf_state.source do
                %{filepath: fp} -> fp
                _ -> nil
              end
              {:ok, %{
                file_path: file_path,
                data: buf_state.data,
                buffer_ref: buf_ref,
                dirty: buf_state.dirty?
              }}

            {:error, reason} ->
              {:error, "Failed to fetch buffer state: #{inspect(reason)}"}
          end
      end
    rescue
      e ->
        {:error, "Failed to get active buffer: #{inspect(e)}"}
    catch
      :exit, reason ->
        {:error, "Buffer process unavailable: #{inspect(reason)}"}
    end
  end

  defp mark_buffer_clean() do
    # Send :save action to the active buffer's process, which sets dirty?: false
    case Quillex.Buffer.active_buf() do
      nil -> :ok
      buf_ref ->
        Quillex.Buffer.BufferManager.call_buffer(buf_ref, {:action, [:mark_clean]})
        :ok
    end
  end

  defp update_buffer_file_path(file_path) do
    case Quillex.Buffer.active_buf() do
      nil ->
        :ok

      buf_ref ->
        # Update the buffer's name and source metadata via the reducer action.
        # {:set_file_path, path} updates name + source without writing to disk,
        # since the caller (save_as/1) has already written the file directly.
        Quillex.Buffer.BufferManager.call_buffer(buf_ref, {:action, [{:set_file_path, file_path}]})
        :ok
    end
  end
end