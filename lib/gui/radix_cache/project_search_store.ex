defmodule Quillex.RadixCache.ProjectSearchStore do
  @moduledoc """
  The project-search RadixCache store: the query, its scope, and the results
  of searching the project tree, published as a full snapshot on the retained
  `:radix_project_search` Scenic.PubSub source.

  The popup search bar is the single text input; while the project pane is
  showing (`ViewStore` `show_project_search`) the scene forwards each query
  change here (`set_query/1`) as well as to the active buffer, so both stay
  in step. Searches run in a task so
  typing never blocks on ripgrep; a newer query supersedes an in-flight one.

  ## Snapshot

      %{
        root: path,                # project root being searched
        query: string,
        status: :idle | :searching | {:done, match_count, file_count, ms} | {:error, term},
        files: [{path, [Match]}],  # results grouped by file, path order
        excluded: MapSet of dirs   # scope: subtrees the user unticked
      }
  """
  use GenServer

  alias Quillex.RadixCache.Sources
  alias Quillex.Search.Project

  @debounce_ms 150
  @max_results 5_000

  @initial %{
    root: nil,
    query: "",
    status: :idle,
    files: [],
    excluded: MapSet.new(),
    # How the query is read. Part of the snapshot because the pane draws the
    # toggles from it, and because a search is only reproducible together with
    # the options it ran under.
    case_sensitive: false,
    regex: false
  }

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  # ── Selectors ──

  @doc "The retained snapshot (instant ETS read)."
  def get_state, do: Scenic.PubSub.get(Sources.project_search())

  # ── Actions (casts — never block the GUI) ──

  @doc "Search under `root`. Idempotent; a different root resets the scope and re-runs."
  def set_root(root) when is_binary(root),
    do: GenServer.cast(__MODULE__, {:set_root, Path.expand(root)})

  @doc "Set the query; the search runs shortly after (debounced while typing)."
  def set_query(query) when is_binary(query), do: GenServer.cast(__MODULE__, {:set_query, query})

  @doc "Include or exclude a directory subtree from the search scope."
  def toggle_scope(dir) when is_binary(dir), do: GenServer.cast(__MODULE__, {:toggle_scope, dir})

  @doc "Flip a search option (`:case_sensitive` or `:regex`) and re-run."
  def toggle_option(option) when option in [:case_sensitive, :regex],
    do: GenServer.cast(__MODULE__, {:toggle_option, option})

  @doc "Set a search option outright."
  def set_option(option, value) when option in [:case_sensitive, :regex] and is_boolean(value),
    do: GenServer.cast(__MODULE__, {:set_option, option, value})

  @doc "The current query options, in the shape the search backends take."
  def search_opts(%{case_sensitive: case_sensitive, regex: regex}),
    do: [case_sensitive: case_sensitive, regex: regex]

  @doc "Replace every current match with `replacement`, then search again."
  def replace_all(replacement) when is_binary(replacement),
    do: GenServer.cast(__MODULE__, {:replace_all, replacement})

  @doc "Synchronous heartbeat: returns once every earlier cast has been processed."
  def sync, do: GenServer.call(__MODULE__, :sync)

  @doc "Block until no search is in flight (tests)."
  def await_idle(timeout \\ 5_000), do: GenServer.call(__MODULE__, :await_idle, timeout)

  # ── GenServer ──

  def init(:ok) do
    Scenic.PubSub.register(Sources.project_search())
    Scenic.PubSub.publish(Sources.project_search(), @initial)
    {:ok, %{view: @initial, task: nil, debounce: nil, waiters: [], started_at: nil}}
  end

  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  def handle_call(:await_idle, _from, %{task: nil, debounce: nil} = state),
    do: {:reply, :ok, state}

  def handle_call(:await_idle, from, state),
    do: {:noreply, %{state | waiters: [from | state.waiters]}}

  def handle_cast({:set_root, root}, %{view: %{root: root}} = state), do: {:noreply, state}

  def handle_cast({:set_root, root}, state) do
    view = %{state.view | root: root, excluded: MapSet.new(), files: [], status: :idle}
    {:noreply, state |> publish(view) |> schedule_search()}
  end

  def handle_cast({:set_query, query}, %{view: %{query: query}} = state), do: {:noreply, state}

  def handle_cast({:set_query, query}, state) do
    {:noreply, state |> publish(%{state.view | query: query}) |> schedule_search()}
  end

  def handle_cast({:toggle_scope, dir}, state) do
    excluded =
      if MapSet.member?(state.view.excluded, dir),
        do: MapSet.delete(state.view.excluded, dir),
        else: MapSet.put(state.view.excluded, dir)

    {:noreply, state |> publish(%{state.view | excluded: excluded}) |> schedule_search()}
  end

  def handle_cast({:toggle_option, option}, state) do
    handle_cast({:set_option, option, not Map.fetch!(state.view, option)}, state)
  end

  def handle_cast({:set_option, option, value}, %{view: view} = state) do
    if Map.fetch!(view, option) == value do
      {:noreply, state}
    else
      {:noreply, state |> publish(Map.put(view, option, value)) |> schedule_search()}
    end
  end

  def handle_cast({:replace_all, replacement}, %{view: %{query: query, files: files} = view} = state)
      when query != "" and files != [] do
    paths = Enum.map(files, fn {path, _matches} -> path end)

    case Project.replace_all(paths, query, replacement, search_opts(view)) do
      {:ok, %{files: n_files, matches: n_matches}} ->
        Quillex.RadixCache.ViewStore.show_status(
          "Replaced #{n_matches} #{plural(n_matches, "match", "matches")} in #{n_files} #{plural(n_files, "file", "files")}",
          :info
        )

        {:noreply, run_search_now(state)}

      {:error, {:bad_pattern, message}} ->
        Quillex.RadixCache.ViewStore.show_status("Replace failed: #{message}", :error)
        {:noreply, state}
    end
  end

  def handle_cast({:replace_all, _replacement}, state), do: {:noreply, state}

  # Debounce fired: start the search unless the query changed again meanwhile.
  def handle_info({:run_search, ref}, %{debounce: ref} = state) do
    {:noreply, run_search_now(%{state | debounce: nil})}
  end

  def handle_info({:run_search, _stale}, state), do: {:noreply, state}

  # Search task finished. Only the CURRENT task's result is published; a
  # superseded search that finishes late is dropped, ref and all.
  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    view =
      case result do
        {:ok, files} ->
          count = files |> Enum.map(fn {_p, ms} -> length(ms) end) |> Enum.sum()
          elapsed = System.monotonic_time(:millisecond) - state.started_at
          %{state.view | files: files, status: {:done, count, length(files), elapsed}}

        {:error, reason} ->
          %{state.view | files: [], status: {:error, reason}}
      end

    state = publish(%{state | task: nil}, view)
    {:noreply, notify_waiters(state)}
  end

  def handle_info({ref, _late_result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: %Task{ref: ref}} = state) do
    state = publish(%{state | task: nil}, %{state.view | status: {:error, reason}})
    {:noreply, notify_waiters(state)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  # ── Internals ──

  defp schedule_search(state) do
    ref = make_ref()
    Process.send_after(self(), {:run_search, ref}, @debounce_ms)
    %{state | debounce: ref}
  end

  defp run_search_now(%{view: %{query: "", root: _}} = state) do
    state = cancel_task(state)
    state |> publish(%{state.view | files: [], status: :idle}) |> notify_waiters()
  end

  defp run_search_now(%{view: %{root: nil}} = state), do: state

  defp run_search_now(%{view: view} = state) do
    state = cancel_task(state)
    root = view.root
    query = view.query
    excludes = MapSet.to_list(view.excluded)

    opts =
      [excludes: excludes, max_results: @max_results] ++ search_opts(view)

    task =
      Task.Supervisor.async_nolink(Quillex.Search.TaskSupervisor, fn ->
        Project.search(root, query, opts)
      end)

    state
    |> Map.merge(%{task: task, started_at: System.monotonic_time(:millisecond)})
    |> publish(%{view | status: :searching})
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

  defp plural(1, singular, _plural), do: singular
  defp plural(_n, _singular, plural), do: plural

  # The single commit point: every mutation publishes the full snapshot.
  defp publish(state, new_view) do
    Scenic.PubSub.publish(Sources.project_search(), new_view)
    %{state | view: new_view}
  end
end
