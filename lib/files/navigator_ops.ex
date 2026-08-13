defmodule Quillex.Files.NavigatorOps do
  @moduledoc """
  Guarded filesystem operations used by the file navigator.

  Operations validate the complete request before touching disk. Moves reject
  missing sources, non-directory targets, destination collisions, self-moves,
  and moving a directory into one of its descendants. After a successful move,
  open buffers beneath the moved paths are repointed through the public buffer
  dispatch boundary so document watching and future saves follow the file.

  Deletion is intentionally a separate call: UI callers must obtain explicit
  confirmation before invoking it.
  """

  alias Quillex.Buffer

  @type move_result :: {:ok, [{binary(), binary()}]} | {:error, term()}

  @doc "Move every selected path into an existing directory."
  @spec move([binary()], binary()) :: move_result()
  def move(paths, target_directory) when is_list(paths) and is_binary(target_directory) do
    sources = paths |> Enum.uniq() |> Enum.map(&Path.expand/1)
    target = Path.expand(target_directory)

    with :ok <- validate_target(target),
         :ok <- validate_sources(sources),
         moves <- Enum.map(sources, &{&1, Path.join(target, Path.basename(&1))}),
         :ok <- validate_moves(moves, target),
         :ok <- perform_moves(moves) do
      repoint_open_buffers(moves)
      {:ok, moves}
    end
  end

  @doc "Delete selected paths recursively. The caller must confirm first."
  @spec delete([binary()]) :: {:ok, [binary()]} | {:error, term()}
  def delete(paths) when is_list(paths) do
    paths = paths |> Enum.uniq() |> Enum.map(&Path.expand/1)

    with :ok <- validate_sources(paths),
         :ok <- perform_deletes(paths) do
      {:ok, paths}
    end
  end

  defp validate_target(target) do
    if File.dir?(target), do: :ok, else: {:error, {:invalid_target, target}}
  end

  defp validate_sources([]), do: {:error, :empty_selection}

  defp validate_sources(sources) do
    case Enum.find(sources, &(not File.exists?(&1))) do
      nil -> :ok
      path -> {:error, {:missing_source, path}}
    end
  end

  defp validate_moves(moves, target) do
    cond do
      Enum.any?(moves, fn {source, _destination} -> source == target end) ->
        {:error, :move_into_self}

      source =
          Enum.find_value(moves, fn {source, _destination} ->
            if File.dir?(source) and descendant?(target, source), do: source
          end) ->
        {:error, {:move_into_descendant, source, target}}

      destination =
          Enum.find_value(moves, fn {source, destination} ->
            if source != destination and File.exists?(destination), do: destination
          end) ->
        {:error, {:destination_exists, destination}}

      Enum.any?(moves, fn {source, destination} -> source == destination end) ->
        {:error, :already_in_target}

      true ->
        :ok
    end
  end

  defp descendant?(candidate, directory) do
    relative = Path.relative_to(candidate, directory)
    relative != candidate and relative != "." and not String.starts_with?(relative, "..")
  end

  defp perform_moves(moves) do
    Enum.reduce_while(moves, {:ok, []}, fn {source, destination} = move, {:ok, completed} ->
      case File.rename(source, destination) do
        :ok ->
          {:cont, {:ok, [move | completed]}}

        {:error, reason} ->
          rollback_moves(completed)
          {:halt, {:error, {:move_failed, source, destination, reason}}}
      end
    end)
    |> case do
      {:ok, _completed} -> :ok
      error -> error
    end
  end

  defp rollback_moves(completed) do
    Enum.each(completed, fn {source, destination} -> File.rename(destination, source) end)
  end

  defp perform_deletes(paths) do
    Enum.reduce_while(paths, :ok, fn path, :ok ->
      case File.rm_rf(path) do
        {:ok, _removed} -> {:cont, :ok}
        {:error, reason, failed_path} -> {:halt, {:error, {:delete_failed, failed_path, reason}}}
      end
    end)
  end

  defp repoint_open_buffers(moves) do
    Enum.each(Buffer.list(), fn ref ->
      if is_binary(ref.path) do
        case moved_path(ref.path, moves) do
          nil -> :ok
          new_path -> Buffer.dispatch(ref, {:set_file_path, new_path})
        end
      end
    end)
  end

  defp moved_path(path, moves) do
    expanded = Path.expand(path)

    Enum.find_value(moves, fn {source, destination} ->
      cond do
        expanded == source ->
          destination

        File.dir?(destination) and descendant?(expanded, source) ->
          Path.join(destination, Path.relative_to(expanded, source))

        true ->
          nil
      end
    end)
  end
end
