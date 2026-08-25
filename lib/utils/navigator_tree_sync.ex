defmodule Quillex.Files.NavigatorTreeSync do
  @moduledoc """
  Keeps the file navigator's directory tree synchronized with disk.

  This service watches the directories the navigator has open rather than open
  buffers. RootScene tells it which those are; it polls a lightweight
  structural signature of each one, one level deep, then asks
  `Quillex.RadixCache.ViewStore` to publish a navigator revision when files or
  directories are created, removed, renamed, or moved. RootScene responds by
  updating the existing SideNav component, allowing the widget to preserve
  expansion and interaction state.

  What is watched is what is *shown*. This used to walk the entire project on
  every tick, to depth, which on a large tree meant a full recursive stat of it
  twice a second — for ever, in the background, to notice that folders nobody
  had opened were unchanged.

  Polling uses ordinary Elixir file APIs and therefore keeps Quillex portable
  and NIF-free. Open document contents remain the separate responsibility of
  `Quillex.Files.ExternalFileSync`.
  """

  use GenServer

  alias Quillex.RadixCache.{Sources, ViewStore}
  alias Quillex.Utils.FileTree

  @default_poll_ms 500

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc false
  def poll_now, do: GenServer.call(__MODULE__, :poll_now)

  @doc """
  Set the directories to watch — the navigator root and every folder open
  under it. An empty list watches nothing, which is what a hidden navigator
  needs.
  """
  def watch(paths) when is_list(paths), do: GenServer.cast(__MODULE__, {:watch, paths})

  @impl GenServer
  def init(opts) do
    Scenic.PubSub.subscribe(Sources.view())

    interval_ms =
      Keyword.get(
        opts,
        :poll_interval_ms,
        Application.get_env(:quillex, :navigator_tree_poll_ms, @default_poll_ms)
      )

    {:ok, schedule(%{paths: [], signature: nil, visible?: false, interval_ms: interval_ms})}
  end

  @impl GenServer
  def handle_cast({:watch, paths}, state) do
    {:noreply, %{state | paths: paths, signature: signature(state.visible?, paths)}}
  end

  @impl GenServer
  def handle_call(:poll_now, _from, state) do
    state = inspect_tree(state)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({{Scenic.PubSub, :data}, {:radix_view, view, _timestamp}}, state) do
    visible? = view.show_file_nav

    state =
      if visible? != state.visible? do
        %{state | visible?: visible?, signature: signature(visible?, state.paths)}
      else
        state
      end

    {:noreply, state}
  end

  def handle_info(:poll, state) do
    {:noreply, state |> Map.put(:timer, nil) |> inspect_tree() |> schedule()}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp inspect_tree(%{visible?: false} = state), do: state
  defp inspect_tree(%{paths: []} = state), do: state

  defp inspect_tree(state) do
    current = FileTree.signature(state.paths)

    if state.signature != nil and current != state.signature do
      ViewStore.refresh_file_nav()
    end

    %{state | signature: current}
  end

  defp signature(true, paths), do: FileTree.signature(paths)
  defp signature(false, _paths), do: nil

  defp schedule(%{interval_ms: interval_ms} = state) when interval_ms > 0 do
    Map.put(state, :timer, Process.send_after(self(), :poll, interval_ms))
  end

  defp schedule(state), do: state
end
