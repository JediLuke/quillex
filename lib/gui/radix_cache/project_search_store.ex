defmodule Quillex.RadixCache.ProjectSearchStore do
  @moduledoc """
  The project-search RadixCache store: the query, its scope, and the results
  of searching the project tree, published as a full snapshot on the retained
  `:radix_project_search` Scenic.PubSub source.

  The pane owns its own query and replacement fields (`Ctrl+Shift+F`); the
  floating find popup (`Ctrl+F`) is a separate thing searching the active
  buffer, and the two never talk. Searches run in a task so typing never blocks
  on ripgrep; a newer query supersedes an in-flight one.

  ## Snapshot

      %{
        root: path,                    # project root being searched
        query: string,
        status: :idle                     # nothing to search, or nothing typed
              | :debouncing               # a keystroke landed; the search has not started
              | :searching                # the task is running
              | {:done, matches, files, ms}
              | {:error, term},
        files: [{path, [Match]}],      # VISIBLE results, grouped by file
        excluded: MapSet of paths,     # scope: files and subtrees unticked
        dismissed: MapSet of {path, line, col},
        dismissed_files: MapSet of path,
        error: nil | String.t(),       # last replace failure, for the pane to show
        case_sensitive: boolean,
        regex: boolean
      }

  The three in-flight states are published, not inferred. While a search is
  pending or running, `files` still holds the PREVIOUS query's results — they
  are the best thing to show, since blanking the pane between keystrokes
  would leave nothing readable while typing — so the status is the only thing
  that can say they are not the answer yet. `ScenicWidgets.SearchPane` fades
  them for exactly as long as it is being told so.

  `files` is what the pane draws AND what every replace path acts on. Dismissed
  matches are removed here, at the single point where results are published, so
  there is no way for a replace to reach one: dismissal is the safety valve
  that makes Replace All reviewable, and a valve that only hides things is not
  one.
  """
  use GenServer

  alias Quillex.RadixCache.Sources
  alias Quillex.Search.Project

  @debounce_ms 150
  # Typing in the editor re-searches only the open buffers, and not on every
  # keystroke. Longer than the query debounce: the person is writing code, not
  # driving the pane.
  @dirty_debounce_ms 400
  @max_results 5_000

  @initial %{
    root: nil,
    query: "",
    status: :idle,
    files: [],
    excluded: MapSet.new(),
    dismissed: MapSet.new(),
    dismissed_files: MapSet.new(),
    error: nil,
    # How the query is read. Part of the snapshot because the pane draws the
    # toggles from it, and because a search is only reproducible together with
    # the options it ran under.
    case_sensitive: false,
    regex: false,
    # Honour the project's own .gitignore. On by default: a project already
    # says what is not source, and searching its build output is never what
    # anybody wanted. Off searches everything the excludes file allows.
    use_ignore_files: true,
    # Search only what is already open. For the times you know the thing you
    # are looking for is in one of the files in front of you, and the rest of
    # the project is noise.
    open_buffers_only: false
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

  @doc "Hide one match from the results, and from every replace path."
  def dismiss_match(path, line, col),
    do: GenServer.cast(__MODULE__, {:dismiss_match, path, line, col})

  @doc "Hide a whole file's matches."
  def dismiss_file(path) when is_binary(path),
    do: GenServer.cast(__MODULE__, {:dismiss_file, path})

  @doc """
  Re-search the buffers with unsaved edits and republish.

  The pane is live for open buffers only: results from disk stay as the last
  search left them, and editing a file the pane is showing updates just that
  file. A tree walk on every keystroke is never worth it.
  """
  def refresh_dirty, do: GenServer.cast(__MODULE__, :refresh_dirty)

  @doc """
  Include or exclude a path from the search scope.

  A directory takes its whole subtree with it; a file is just itself. The
  backend matches on path segments, so both are the same rule.
  """
  def toggle_scope(path) when is_binary(path),
    do: GenServer.cast(__MODULE__, {:toggle_scope, path})

  @doc "Flip a search option (`:case_sensitive` or `:regex`) and re-run."
  def toggle_option(option)
      when option in [:case_sensitive, :regex, :use_ignore_files, :open_buffers_only],
    do: GenServer.cast(__MODULE__, {:toggle_option, option})

  @doc "Set a search option outright."
  def set_option(option, value) when option in [:case_sensitive, :regex] and is_boolean(value),
    do: GenServer.cast(__MODULE__, {:set_option, option, value})

  @doc "The current query options, in the shape the search backends take."
  def search_opts(%{case_sensitive: case_sensitive, regex: regex}),
    do: [case_sensitive: case_sensitive, regex: regex]

  @doc "Replace every visible match with `replacement`, then search again."
  def replace_all(replacement) when is_binary(replacement),
    do: GenServer.cast(__MODULE__, {:replace_all, replacement})

  @doc "Replace every visible match in one file."
  def replace_file(path, replacement) when is_binary(path) and is_binary(replacement),
    do: GenServer.cast(__MODULE__, {:replace_file, path, replacement})

  @doc "Replace exactly one match."
  def replace_match(path, line, col, replacement) when is_binary(replacement),
    do: GenServer.cast(__MODULE__, {:replace_match, path, line, col, replacement})

  @doc "Synchronous heartbeat: returns once every earlier cast has been processed."
  def sync, do: GenServer.call(__MODULE__, :sync)

  @doc "Block until no search is in flight (tests)."
  def await_idle(timeout \\ 5_000), do: GenServer.call(__MODULE__, :await_idle, timeout)

  # ── GenServer ──

  def init(:ok) do
    Scenic.PubSub.register(Sources.project_search())
    Scenic.PubSub.publish(Sources.project_search(), @initial)

    # The pane is live for open buffers: editing a file the results are showing
    # updates that file's rows. Subscribing to the pane source is how we hear
    # about it — it publishes the document on every change, which is precisely
    # "as you type".
    Scenic.PubSub.subscribe(Quillex.RadixCache.PaneStore.source())

    {:ok,
     %{
       view: @initial,
       raw_files: [],
       task: nil,
       task_query: nil,
       partial_ref: nil,
       debounce: nil,
       dirty_debounce: nil,
       waiters: [],
       started_at: nil
     }}
  end

  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  def handle_call(:await_idle, _from, %{task: nil, debounce: nil} = state),
    do: {:reply, :ok, state}

  def handle_call(:await_idle, from, state),
    do: {:noreply, %{state | waiters: [from | state.waiters]}}

  def handle_cast({:set_root, root}, %{view: %{root: root}} = state), do: {:noreply, state}

  def handle_cast({:set_root, root}, state) do
    view = %{state.view | root: root, excluded: MapSet.new(), files: [], status: :idle}
    {:noreply, state |> restart_search(view)}
  end

  def handle_cast({:set_query, query}, %{view: %{query: query}} = state), do: {:noreply, state}

  def handle_cast({:set_query, query}, state),
    do: {:noreply, restart_search(state, %{state.view | query: query})}

  def handle_cast({:toggle_scope, path}, state) do
    excluded =
      if MapSet.member?(state.view.excluded, path),
        do: MapSet.delete(state.view.excluded, path),
        else: MapSet.put(state.view.excluded, path)

    {:noreply, restart_search(state, %{state.view | excluded: excluded})}
  end

  def handle_cast({:toggle_option, option}, state) do
    handle_cast({:set_option, option, not Map.fetch!(state.view, option)}, state)
  end

  def handle_cast({:set_option, option, value}, %{view: view} = state) do
    if Map.fetch!(view, option) == value do
      {:noreply, state}
    else
      {:noreply, restart_search(state, Map.put(view, option, value))}
    end
  end

  # Dismissals do not re-run anything: they hide matches the search already
  # found. Republishing from the raw results is the whole of it.
  def handle_cast({:dismiss_match, path, line, col}, %{view: view} = state) do
    dismissed = MapSet.put(view.dismissed, {path, line, col})
    {:noreply, publish_visible(state, %{view | dismissed: dismissed})}
  end

  def handle_cast({:dismiss_file, path}, %{view: view} = state) do
    dismissed_files = MapSet.put(view.dismissed_files, path)
    {:noreply, publish_visible(state, %{view | dismissed_files: dismissed_files})}
  end

  def handle_cast(:refresh_dirty, %{view: %{root: nil}} = state), do: {:noreply, state}
  def handle_cast(:refresh_dirty, %{view: %{query: ""}} = state), do: {:noreply, state}

  def handle_cast(:refresh_dirty, %{view: view} = state) do
    raw = Project.refresh_dirty(state.raw_files, view.root, view.query, backend_opts(view))
    {:noreply, publish_visible(%{state | raw_files: raw}, view)}
  end

  def handle_cast({:replace_all, replacement}, %{view: view} = state),
    do: {:noreply, do_replace(state, view.files, replacement)}

  def handle_cast({:replace_file, path, replacement}, %{view: view} = state),
    do: {:noreply, do_replace(state, Enum.filter(view.files, &(elem(&1, 0) == path)), replacement)}

  def handle_cast({:replace_match, path, line, col, replacement}, %{view: view} = state) do
    selected =
      view.files
      |> Enum.filter(fn {file_path, _matches} -> file_path == path end)
      |> Enum.map(fn {file_path, matches} ->
        {file_path, Enum.filter(matches, &(&1.line == line and &1.col == col))}
      end)

    {:noreply, do_replace(state, selected, replacement)}
  end

  # The active document changed. Nothing to do unless a search is actually
  # showing results this could contradict.
  def handle_info({{Scenic.PubSub, :data}, {_pane_source, _document, _ts}}, state) do
    if state.view.root && state.view.query != "" do
      ref = make_ref()
      Process.send_after(self(), {:refresh_dirty, ref}, @dirty_debounce_ms)
      {:noreply, %{state | dirty_debounce: ref}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:refresh_dirty, ref}, %{dirty_debounce: ref} = state) do
    handle_cast(:refresh_dirty, %{state | dirty_debounce: nil})
  end

  def handle_info({:refresh_dirty, _stale}, state), do: {:noreply, state}

  # Scenic.PubSub lifecycle notifications for the source we subscribe to.
  def handle_info({{Scenic.PubSub, :registered}, _}, state), do: {:noreply, state}
  def handle_info({{Scenic.PubSub, :unregistered}, _}, state), do: {:noreply, state}

  # A search in progress has found some of it. Published exactly like a
  # finished one except for the status, which still says :searching — so the
  # pane draws these rows faded, under a "searching…" line, which is what a
  # provisional answer should look like.
  def handle_info({:partial_results, ref, partial}, %{partial_ref: ref} = state) do
    {:noreply, publish_visible(%{state | raw_files: partial}, state.view)}
  end

  # A report from a search that has been superseded. Dropped, ref and all —
  # the same reason its final result would be.
  def handle_info({:partial_results, _stale, _partial}, state), do: {:noreply, state}

  # Debounce fired: start the search unless the query changed again meanwhile.
  def handle_info({:run_search, ref}, %{debounce: ref} = state) do
    {:noreply, run_search_now(%{state | debounce: nil})}
  end

  def handle_info({:run_search, _stale}, state), do: {:noreply, state}

  # Search task finished. Only the CURRENT task's result is published; a
  # superseded search that finishes late is dropped, ref and all.
  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    state =
      cond do
        # Results for a query that is no longer the one in the box. Dropped,
        # not published: the search that IS current is either running or about
        # to be, and its answer is the one that belongs to this query.
        state.task_query != {state.view.query, backend_opts(state.view)} ->
          %{state | task: nil, partial_ref: nil}

        match?({:ok, _}, result) ->
          {:ok, files} = result
          elapsed = System.monotonic_time(:millisecond) - state.started_at

          %{state | task: nil, partial_ref: nil, raw_files: files}
          |> publish_visible(state.view, elapsed)

        match?({:error, {:bad_pattern, _}}, result) ->
          {:error, {:bad_pattern, message}} = result

          %{state | task: nil, partial_ref: nil, raw_files: []}
          |> publish(%{state.view | files: [], status: :idle, error: message})

        true ->
          {:error, reason} = result

          %{state | task: nil, partial_ref: nil, raw_files: []}
          |> publish(%{state.view | files: [], status: {:error, reason}})
      end

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

  # Anything that changes WHAT is searched starts over, dismissals included:
  # they are judgements about a particular result set, and this is a different
  # one. A re-run after a replace deliberately does not come through here —
  # there, the matches the user dismissed are exactly the ones still standing.
  defp restart_search(state, view) do
    state
    |> publish(%{
      view
      | dismissed: MapSet.new(),
        dismissed_files: MapSet.new(),
        error: nil,
        status: pending_status(view)
    })
    |> schedule_search()
  end

  # A keystroke has landed and the search has not started yet. Published
  # rather than left at whatever the last search said, because for those
  # 150ms the results on screen answer a query that is no longer in the box —
  # and the pane's only way to know that is to be told.
  #
  # An empty query is not pending anything; there is nothing to search.
  defp pending_status(%{query: ""}), do: :idle
  defp pending_status(_view), do: :debouncing

  defp schedule_search(state) do
    ref = make_ref()
    Process.send_after(self(), {:run_search, ref}, @debounce_ms)
    %{state | debounce: ref}
  end

  defp run_search_now(%{view: %{query: "", root: _}} = state) do
    state = cancel_task(state)

    %{state | raw_files: []}
    |> publish(%{state.view | files: [], status: :idle})
    |> notify_waiters()
  end

  defp run_search_now(%{view: %{root: nil}} = state), do: state

  defp run_search_now(%{view: view} = state) do
    state = cancel_task(state)
    root = view.root
    query = view.query
    opts = backend_opts(view)

    # The task reports in as it walks. `partial_ref` is what tells a report
    # from THIS search apart from one still arriving from the last: a search
    # superseded mid-walk goes on sending for as long as it takes to die, and
    # its results must not land in the pane under the new query's name.
    partial_ref = make_ref()
    store = self()

    task =
      Task.Supervisor.async_nolink(Quillex.Search.TaskSupervisor, fn ->
        Project.search_streaming(root, query, opts, fn partial ->
          send(store, {:partial_results, partial_ref, partial})
        end)
      end)

    state
    |> Map.merge(%{
      task: task,
      # What this task is searching for. A task started for an earlier query
      # can finish AFTER a newer one was scheduled but before it ran — and its
      # results would then be published under the newer query's label, which
      # is simply wrong. Matching on the ref alone does not catch it.
      task_query: {query, opts},
      partial_ref: partial_ref,
      started_at: System.monotonic_time(:millisecond)
    })
    |> publish(%{view | status: :searching, error: nil})
  end

  # What a search skips, assembled per search from three places that each
  # answer a different question:
  #
  #   the excludes file — "never search this, in any project" (yours to edit)
  #   the project's .gitignore — "this project says this is not source"
  #   the scope tree — "not this, for THIS search"
  #
  # The first two are globs and go in together; the third is a set of paths.
  defp backend_opts(view) do
    ignore_patterns =
      if view.use_ignore_files and view.root,
        do: Quillex.Search.IgnoreFile.rules(view.root),
        else: %{ignore: [], unignore: []}

    [
      excludes: MapSet.to_list(view.excluded),
      exclude_globs: Quillex.Search.Excludes.patterns() ++ ignore_patterns.ignore,
      unignore_globs: ignore_patterns.unignore,
      open_buffers_only: view.open_buffers_only,
      max_results: @max_results
    ] ++ search_opts(view)
  end

  defp do_replace(state, [], _replacement), do: state

  defp do_replace(state, files, replacement) do
    {:ok, %{files: n_files, matches: n_matches}} = Project.replace_matches(files, replacement)

    Quillex.RadixCache.ViewStore.show_status(
      "Replaced #{n_matches} #{plural(n_matches, "match", "matches")} in #{n_files} #{plural(n_files, "file", "files")}",
      :info
    )

    run_search_now(state)
  end

  # Publish the raw results minus whatever the user has dismissed. The status
  # counts what is VISIBLE — a count that included dismissed matches would
  # contradict the rows right underneath it.
  defp publish_visible(state, view, elapsed \\ nil) do
    files = visible(state.raw_files, view)
    count = files |> Enum.map(fn {_path, matches} -> length(matches) end) |> Enum.sum()

    status =
      case {elapsed, view.status} do
        {nil, {:done, _n, _files, ms}} -> {:done, count, length(files), ms}
        {nil, other} -> other
        {ms, _} -> {:done, count, length(files), ms}
      end

    publish(state, %{view | files: files, status: status, error: nil})
  end

  defp visible(raw_files, view) do
    raw_files
    |> Enum.reject(fn {path, _matches} -> MapSet.member?(view.dismissed_files, path) end)
    |> Enum.map(fn {path, matches} ->
      {path,
       Enum.reject(matches, &MapSet.member?(view.dismissed, {&1.path, &1.line, &1.col}))}
    end)
    |> Enum.reject(fn {_path, matches} -> matches == [] end)
  end

  defp cancel_task(%{task: nil} = state), do: state

  defp cancel_task(%{task: task} = state) do
    Task.shutdown(task, :brutal_kill)
    # The ref goes with it: anything still in the mailbox from this search is
    # now a report about a query nobody asked.
    %{state | task: nil, task_query: nil, partial_ref: nil}
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
