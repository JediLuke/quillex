defmodule Quillex.Files.ExternalFileSync do
  @moduledoc """
  Keeps open file-backed buffers synchronized with their files on disk.

  The service is part of the common buffer backend, so it runs in standalone
  and headless modes. It polls with ordinary Elixir/OTP file APIs;
  no platform watcher, NIF, or GUI process owns document synchronization.

  Each open canonical path has a remembered disk-content digest. A changed
  clean file is reloaded through `Quillex.Buffer`; a changed dirty file is
  preserved and marked with durable conflict metadata. Comparing the new disk
  content with the live buffer also suppresses the filesystem reflection of
  Quillex's own save without a timing window.
  """

  use GenServer
  require Logger

  alias Quillex.Buffer
  alias Quillex.RadixCache.Sources
  alias Quillex.RadixCache.ViewStore

  @default_poll_ms 500

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  def poll_now do
    GenServer.call(__MODULE__, :poll_now)
  end

  @doc false
  def sync do
    GenServer.call(__MODULE__, :sync)
  end

  @impl GenServer
  def init(opts) do
    Scenic.PubSub.subscribe(Sources.buffers())

    interval_ms =
      Keyword.get(
        opts,
        :poll_interval_ms,
        Application.get_env(:quillex, :external_file_poll_ms, @default_poll_ms)
      )

    state = %{entries: %{}, interval_ms: interval_ms, timer: nil}
    {:ok, schedule(state)}
  end

  @impl GenServer
  def handle_call(:sync, _from, state), do: {:reply, :ok, refresh_entries(state)}

  def handle_call(:poll_now, _from, state) do
    state = state |> refresh_entries() |> poll_entries()
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(
        {{Scenic.PubSub, :data}, {:radix_buffers, %{buffers: buffers}, _timestamp}},
        state
      ) do
    {:noreply, sync_entries(state, buffers)}
  end

  def handle_info(:poll, state) do
    state = state |> Map.put(:timer, nil) |> refresh_entries() |> poll_entries()
    {:noreply, schedule(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp refresh_entries(state) do
    sync_entries(state, Buffer.list())
  catch
    :exit, _reason -> state
  end

  defp sync_entries(state, buffers) do
    entries =
      buffers
      |> Enum.filter(&(is_binary(&1.path) and &1.path != ""))
      |> Map.new(fn ref ->
        case Map.get(state.entries, ref.uuid) do
          %{path: path} = existing when path == ref.path ->
            {ref.uuid, %{existing | ref: ref}}

          _new_or_repointed ->
            {ref.uuid, %{ref: ref, path: ref.path, disk: disk_state(ref.path)}}
        end
      end)

    %{state | entries: entries}
  end

  defp poll_entries(state) do
    entries =
      Map.new(state.entries, fn {uuid, entry} ->
        current_disk = disk_state(entry.path)
        {uuid, reconcile(entry, current_disk)}
      end)

    %{state | entries: entries}
  end

  defp reconcile(%{disk: disk} = entry, disk), do: entry

  defp reconcile(entry, {:ok, disk_digest, content} = current_disk) do
    case Buffer.fetch(entry.ref) do
      {:ok, snapshot} ->
        buffer_content = Enum.join(snapshot.lines, "\n")

        cond do
          digest(buffer_content) == disk_digest ->
            maybe_clear_conflict(snapshot)

          snapshot.ref.dirty? ->
            mark_conflict(snapshot.ref, :modified)

          true ->
            reload(snapshot.ref, content)
        end

      {:error, reason} ->
        Logger.debug("external file sync skipped #{entry.path}: #{inspect(reason)}")
    end

    %{entry | disk: current_disk}
  end

  defp reconcile(entry, :missing) do
    if entry.disk != :missing do
      case Buffer.fetch(entry.ref) do
        {:ok, snapshot} -> mark_conflict(snapshot.ref, :deleted)
        {:error, _reason} -> :ok
      end
    end

    %{entry | disk: :missing}
  end

  defp reconcile(entry, {:error, reason} = error) do
    if entry.disk != error do
      Logger.warning("Cannot inspect #{entry.path}: #{inspect(reason)}")

      ViewStore.show_status(
        "Cannot read #{Path.basename(entry.path)}: #{inspect(reason)}",
        :warning
      )
    end

    %{entry | disk: error}
  end

  defp reload(ref, content) do
    lines = String.split(content, "\n")

    case Buffer.reload_if_clean(ref, lines) do
      {:ok, _snapshot} ->
        ViewStore.show_status("Reloaded #{display_name(ref)} from disk", :info)

      {:error, :dirty} ->
        mark_conflict(ref, :modified)

      {:error, reason} ->
        Logger.warning("Failed to reload #{ref.path}: #{inspect(reason)}")
        ViewStore.show_status("Failed to reload #{display_name(ref)}", :warning)
    end
  end

  defp mark_conflict(ref, change) do
    case Buffer.dispatch(ref, {:mark_external_change, change}) do
      {:ok, _snapshot} ->
        message =
          case change do
            :modified -> "#{display_name(ref)} changed on disk; unsaved edits preserved"
            :deleted -> "#{display_name(ref)} was deleted on disk; buffer preserved"
          end

        ViewStore.show_status(message, :warning)

      {:error, reason} ->
        Logger.warning("Failed to mark external change for #{ref.path}: #{inspect(reason)}")
    end
  end

  defp maybe_clear_conflict(%{ref: %{external_change: nil}}), do: :ok

  defp maybe_clear_conflict(snapshot) do
    Buffer.dispatch(snapshot.ref, :clear_external_change)
    :ok
  end

  defp disk_state(path) do
    case Quillex.Files.TextFile.read(path) do
      {:ok, content} -> {:ok, digest(content), content}
      {:error, :enoent} -> :missing
      {:error, reason} -> {:error, reason}
    end
  end

  defp digest(content), do: :erlang.phash2(content)

  defp display_name(%{path: path}) when is_binary(path), do: Path.basename(path)
  defp display_name(%{name: name}), do: name

  defp schedule(%{interval_ms: interval_ms} = state)
       when is_integer(interval_ms) and interval_ms > 0 do
    %{state | timer: Process.send_after(self(), :poll, interval_ms)}
  end

  defp schedule(state), do: state
end
