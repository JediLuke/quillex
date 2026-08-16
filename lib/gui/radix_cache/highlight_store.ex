defmodule Quillex.RadixCache.HighlightStore do
  @moduledoc """
  The highlighting RadixCache store: token spans for the document the pane
  shows, published on the retained `:radix_highlights` source as
  `%{buffer_id: uuid, lines: Quillex.Highlight.lines() | nil}`.

  Follows the pane source (`Quillex.RadixCache.PaneStore`), so it sees the
  same document the TextField does. Text changes are lexed off-process
  after a short debounce; results are cached per buffer by content hash, so
  switching back to a document is instant. `lines: nil` means "no lexer for
  this file" and the pane draws plain text.
  """
  use GenServer

  alias Quillex.RadixCache.{PaneStore, Sources}
  alias Quillex.Highlight

  @debounce_ms 120

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "The retained source — what a TextField passes as `highlight_source`."
  def source, do: Sources.highlights()

  @doc "Synchronous heartbeat for tests: returns once no lex is pending or running."
  def await_idle(timeout \\ 5_000), do: GenServer.call(__MODULE__, :await_idle, timeout)

  # ── GenServer ──

  def init(:ok) do
    Scenic.PubSub.register(Sources.highlights())
    Scenic.PubSub.subscribe(PaneStore.source())

    {:ok,
     %{
       buffer_id: nil,
       lexer: nil,
       lines: [],
       hash: nil,
       cache: %{},
       task: nil,
       debounce: nil,
       waiters: []
     }}
  end

  def handle_call(:await_idle, _from, %{task: nil, debounce: nil} = state),
    do: {:reply, :ok, state}

  def handle_call(:await_idle, from, state),
    do: {:noreply, %{state | waiters: [from | state.waiters]}}

  # The pane's document: (re)lex when its text or file changes.
  def handle_info({{Scenic.PubSub, :data}, {_pane_source, buf, _ts}}, state) do
    uuid = buf.uuid
    lines = buf.data
    lexer = Highlight.lexer_for_path(source_path(buf.source))
    hash = :erlang.phash2({lexer, lines})

    cond do
      uuid == state.buffer_id and hash == state.hash ->
        {:noreply, state}

      lexer == nil ->
        publish(uuid, nil)
        {:noreply, %{state | buffer_id: uuid, lexer: nil, lines: lines, hash: hash}}

      true ->
        state = %{state | buffer_id: uuid, lexer: lexer, lines: lines, hash: hash}

        case Map.get(state.cache, uuid) do
          {^hash, spans} ->
            publish(uuid, spans)
            {:noreply, state}

          _ ->
            {:noreply, schedule(state)}
        end
    end
  end

  def handle_info({:lex, ref}, %{debounce: ref} = state) do
    state = cancel_task(%{state | debounce: nil})
    %{buffer_id: uuid, lexer: lexer, lines: lines, hash: hash} = state

    task =
      Task.Supervisor.async_nolink(Quillex.Search.TaskSupervisor, fn ->
        {uuid, hash, Highlight.spans(lines, lexer)}
      end)

    {:noreply, %{state | task: task}}
  end

  def handle_info({:lex, _stale}, state), do: {:noreply, state}

  def handle_info({ref, {uuid, hash, spans}}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    publish(uuid, spans)
    cache = Map.put(state.cache, uuid, {hash, spans})
    {:noreply, notify_waiters(%{state | task: nil, cache: cache})}
  end

  def handle_info({ref, _late}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task: %Task{ref: ref}} = state) do
    # A lexer that raised on this text: draw it plain rather than retry forever.
    publish(state.buffer_id, nil)
    {:noreply, notify_waiters(%{state | task: nil})}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}
  def handle_info({{Scenic.PubSub, :registered}, _}, state), do: {:noreply, state}
  def handle_info({{Scenic.PubSub, :unregistered}, _}, state), do: {:noreply, state}

  # ── Internals ──

  defp schedule(state) do
    ref = make_ref()
    Process.send_after(self(), {:lex, ref}, @debounce_ms)
    %{state | debounce: ref}
  end

  defp cancel_task(%{task: nil} = state), do: state

  defp cancel_task(%{task: task} = state) do
    Task.shutdown(task, :brutal_kill)
    %{state | task: nil}
  end

  defp notify_waiters(%{task: nil, debounce: nil, waiters: waiters} = state) do
    Enum.each(waiters, &GenServer.reply(&1, :ok))
    %{state | waiters: []}
  end

  defp notify_waiters(state), do: state

  defp source_path(%{filepath: path}) when is_binary(path), do: path
  defp source_path(_), do: nil

  # The single commit point.
  defp publish(uuid, lines) do
    Scenic.PubSub.publish(Sources.highlights(), %{buffer_id: uuid, lines: lines})
  end
end
