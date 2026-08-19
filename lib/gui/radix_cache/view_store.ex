defmodule Quillex.RadixCache.ViewStore do
  @moduledoc """
  The UI-chrome RadixCache store: editor settings, layout flags, dialogs and
  the transient status message. Publishes its full state map on the retained
  `:radix_view` Scenic.PubSub source; every reducer funnels through one
  `publish/1` commit point.

  RootScene subscribes and re-renders from snapshots. Action functions are
  casts — they never block the GUI process.

  ## Transient status bar

  Features can show a short notification in the colored strip at the bottom
  of the editor through the store action:

      ViewStore.show_status("Reloaded notes.ex from disk", :info)

  The supported severities are `:info`, `:warning`, and `:error`; the root
  renderizer maps them to the strip's background color. A notification is
  replaced by the next one and clears itself after eight seconds. Call this
  action directly from application processes. RootScene has a private wrapper
  only for scene event handlers that must also return a Scenic callback tuple.

  Low-level, successful editor operations use `show_action_feedback/1` instead.
  Those messages share the same strip and lifetime, but respect the optional
  **View → Action Feedback** toggle. Errors and ordinary status notifications
  always remain visible regardless of that preference.
  """
  use GenServer

  alias Quillex.RadixCache.Sources

  @status_clear_ms 8_000
  @file_nav_width_range 160..800

  @initial %{
    # Editor settings (View menu toggles)
    show_line_numbers: true,
    show_matching_brace: true,
    highlight_current_line: false,
    highlight_current_column: false,
    word_wrap: false,
    # Does Enter carry the current line's indentation down to the new line?
    # On by default — it is what the editor has always done, and what you want
    # in code. Off is what you want when typing prose or a list.
    auto_indent: true,
    tab_width: 4,
    text_size: 24,
    fold_level: 1,
    show_menu_shortcuts: true,
    # How project-search results are shown: :tree groups matches under their
    # file, :list gives one row per match. Which is better depends on whether
    # you are looking for a file or for an occurrence, so it is a preference
    # rather than a mode — and one worth keeping between sessions.
    search_results_view: :tree,
    # Structural syntax highlighting (weight/slant/underline by token class)
    syntax_highlighting: true,
    # The colour scheme for editor AND chrome alike — see Quillex.GUI.Palette.
    # One palette drives both: a light buffer inside a dark sidebar reads as
    # broken, not as a theme.
    theme: :alchemical_dark,
    chrome_zoom: 100,
    # File navigator sidebar
    show_file_nav: false,
    file_nav_path: nil,
    file_nav_width: 250,
    file_nav_revision: 0,
    # Project-search results pane. Shares the sidebar slot (and width) with the
    # file navigator and takes precedence over it while open.
    show_project_search: false,
    # Search bar (flags owned here from Phase 6b)
    show_search_bar: false,
    show_replace: false,
    # Optional low-level confirmations such as copy, paste and undo.
    show_action_feedback: true,
    # Modal dialogs (owned here from Phase 6b)
    show_file_picker: false,
    show_unsaved_prompt: false,
    pending_close_buf_ref: nil,
    # Transient status notification (auto-cleared by a timer in this store)
    status_message: nil,
    status_severity: :info
  }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  # ── Selectors ──

  @doc "The retained view-state snapshot (instant ETS read)."
  def get_state, do: Scenic.PubSub.get(Sources.view())

  # ── Actions (casts — never block the GUI) ──

  def toggle_line_numbers, do: GenServer.cast(__MODULE__, :toggle_line_numbers)
  def toggle_matching_brace, do: GenServer.cast(__MODULE__, :toggle_matching_brace)

  def toggle_current_line_highlight,
    do: GenServer.cast(__MODULE__, :toggle_current_line_highlight)

  def toggle_current_column_highlight,
    do: GenServer.cast(__MODULE__, :toggle_current_column_highlight)

  def toggle_word_wrap, do: GenServer.cast(__MODULE__, :toggle_word_wrap)
  def toggle_auto_indent, do: GenServer.cast(__MODULE__, :toggle_auto_indent)

  @doc "Set auto-indent outright, rather than flipping it."
  def set_auto_indent(on?) when is_boolean(on?),
    do: GenServer.cast(__MODULE__, {:set_auto_indent, on?})

  def set_search_results_view(view) when view in [:tree, :list],
    do: GenServer.cast(__MODULE__, {:set_search_results_view, view})

  # Set rather than flip. A caller that wants a guide OFF has to read the
  # current value first to know whether to toggle, and then it is racing every
  # other thing that can change it.
  def set_current_line_highlight(on?) when is_boolean(on?),
    do: GenServer.cast(__MODULE__, {:set_current_line_highlight, on?})

  def set_current_column_highlight(on?) when is_boolean(on?),
    do: GenServer.cast(__MODULE__, {:set_current_column_highlight, on?})
  def toggle_file_nav, do: GenServer.cast(__MODULE__, :toggle_file_nav)
  def toggle_action_feedback, do: GenServer.cast(__MODULE__, :toggle_action_feedback)
  def toggle_menu_shortcuts, do: GenServer.cast(__MODULE__, :toggle_menu_shortcuts)
  def toggle_syntax_highlighting, do: GenServer.cast(__MODULE__, :toggle_syntax_highlighting)

  @doc "Show the file-navigator sidebar. Idempotent, unlike `toggle_file_nav/0`."
  def open_file_nav, do: GenServer.cast(__MODULE__, :open_file_nav)

  @doc "Close the file navigator. The counterpart to open_file_nav/0 — toggling is not the same thing when you need a known state."
  def close_file_nav, do: GenServer.cast(__MODULE__, :close_file_nav)

  @doc """
  Close the file navigator and say so, in ONE published snapshot.

  Closing it and raising the status message separately publishes twice a few
  milliseconds apart, and both are layout changes — the sidebar going away,
  then the status strip appearing. That is two full chrome rebuilds in a row,
  and the second can delete a component the first has only just started. One
  commit, one rebuild.
  """
  def close_file_nav(status) when is_binary(status),
    do: GenServer.cast(__MODULE__, {:close_file_nav, status})

  @doc "Show the project-search results pane in the sidebar slot. Idempotent."
  def open_project_search, do: GenServer.cast(__MODULE__, :open_project_search)

  @doc "Hide the project-search pane; the file navigator (if on) shows again."
  def close_project_search, do: GenServer.cast(__MODULE__, :close_project_search)

  @doc "Set the remembered file-navigator width in pixels."
  def set_file_nav_width(width) when is_integer(width) and width in @file_nav_width_range do
    GenServer.cast(__MODULE__, {:set_file_nav_width, width})
  end

  @doc "Notify subscribers that the filesystem tree beneath the navigator root changed."
  def refresh_file_nav, do: GenServer.cast(__MODULE__, :refresh_file_nav)

  @doc "Set the root directory displayed by the file navigator."
  def set_file_nav_path(path) when is_binary(path) do
    GenServer.cast(__MODULE__, {:set_file_nav_path, Path.expand(path)})
  end

  def set_tab_width(n) when is_integer(n) and n in 2..12 do
    GenServer.cast(__MODULE__, {:set_tab_width, n})
  end

  def set_text_size(n) when is_integer(n) and n in 12..32 do
    GenServer.cast(__MODULE__, {:set_text_size, n})
  end

  def set_fold_level(n) when is_integer(n) and n in 1..4 do
    GenServer.cast(__MODULE__, {:set_fold_level, n})
  end

  @doc "Choose the colour scheme. See `Quillex.GUI.Palette.themes/0`."
  def set_theme(id) when is_atom(id) do
    true = Quillex.GUI.Palette.known?(id)
    GenServer.cast(__MODULE__, {:set_theme, id})
  end

  def set_chrome_zoom(n) when is_integer(n) and n in 50..200,
    do: GenServer.cast(__MODULE__, {:set_chrome_zoom, n})

  @doc "Show a transient status-bar message; the store clears it after eight seconds."
  def show_status(message, severity)
      when is_binary(message) and severity in [:info, :warning, :error] do
    GenServer.cast(__MODULE__, {:show_status, message, severity})
  end

  @doc "Show low-level editor feedback when the View preference is enabled."
  def show_action_feedback(message) when is_binary(message) do
    GenServer.cast(__MODULE__, {:show_action_feedback, message})
  end

  @doc """
  Synchronous heartbeat: returns after all casts queued before this call have
  been processed. Lets tests observe a burst of casts deterministically.
  """
  def sync, do: GenServer.call(__MODULE__, :sync)

  # ── GenServer ──

  def init(:ok) do
    Scenic.PubSub.register(Sources.view())

    # Saved defaults, if the person ever chose to save any (View → Save
    # Settings as Default). Merged over the built-in defaults, so a settings
    # file that names only two keys changes only those two.
    view =
      %{@initial | file_nav_path: File.cwd!()}
      |> Map.merge(Quillex.SettingsFile.load())
    Scenic.PubSub.publish(Sources.view(), view)
    # status_ref stamps the current status message so a stale clear-timer
    # cannot erase a newer message — bookkeeping, deliberately NOT published
    {:ok, %{view: view, status_ref: nil}}
  end

  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  def handle_cast(:toggle_line_numbers, state) do
    {:noreply,
     publish(state, %{state.view | show_line_numbers: not state.view.show_line_numbers})}
  end

  def handle_cast(:toggle_matching_brace, state) do
    {:noreply,
     publish(state, %{state.view | show_matching_brace: not state.view.show_matching_brace})}
  end

  def handle_cast(:toggle_auto_indent, state) do
    {:noreply, publish(state, %{state.view | auto_indent: not state.view.auto_indent})}
  end

  def handle_cast({:set_auto_indent, on?}, state) do
    {:noreply, publish(state, %{state.view | auto_indent: on?})}
  end

  def handle_cast({:set_search_results_view, view}, state) do
    {:noreply, publish(state, %{state.view | search_results_view: view})}
  end

  def handle_cast({:set_current_line_highlight, on?}, state) do
    {:noreply, publish(state, %{state.view | highlight_current_line: on?})}
  end

  def handle_cast({:set_current_column_highlight, on?}, state) do
    {:noreply, publish(state, %{state.view | highlight_current_column: on?})}
  end

  def handle_cast(:toggle_current_line_highlight, state) do
    {:noreply,
     publish(state, %{state.view | highlight_current_line: not state.view.highlight_current_line})}
  end

  def handle_cast(:toggle_current_column_highlight, state) do
    {:noreply,
     publish(state, %{
       state.view
       | highlight_current_column: not state.view.highlight_current_column
     })}
  end

  def handle_cast(:toggle_word_wrap, state) do
    {:noreply, publish(state, %{state.view | word_wrap: not state.view.word_wrap})}
  end

  def handle_cast(:toggle_file_nav, state) do
    {:noreply, publish(state, %{state.view | show_file_nav: not state.view.show_file_nav})}
  end

  def handle_cast(:toggle_action_feedback, state) do
    {:noreply,
     publish(state, %{state.view | show_action_feedback: not state.view.show_action_feedback})}
  end

  def handle_cast(:toggle_menu_shortcuts, state) do
    {:noreply,
     publish(state, %{state.view | show_menu_shortcuts: not state.view.show_menu_shortcuts})}
  end

  def handle_cast(:toggle_syntax_highlighting, state) do
    {:noreply,
     publish(state, %{state.view | syntax_highlighting: not state.view.syntax_highlighting})}
  end

  def handle_cast(:close_file_nav, state) do
    {:noreply, publish(state, %{state.view | show_file_nav: false})}
  end

  def handle_cast({:close_file_nav, status}, state) do
    ref = make_ref()
    Process.send_after(self(), {:clear_status, ref}, @status_clear_ms)

    state =
      publish(state, %{
        state.view
        | show_file_nav: false,
          status_message: status,
          status_severity: :info
      })

    {:noreply, %{state | status_ref: ref}}
  end

  def handle_cast(:open_file_nav, state) do
    {:noreply, publish(state, %{state.view | show_file_nav: true})}
  end

  # Results rows are wider than file names: give the pane room the first time,
  # but never shrink a width the user chose.
  @project_search_min_width 360

  def handle_cast(:open_project_search, state) do
    width = max(state.view.file_nav_width, @project_search_min_width)
    {:noreply, publish(state, %{state.view | show_project_search: true, file_nav_width: width})}
  end

  def handle_cast(:close_project_search, state) do
    {:noreply, publish(state, %{state.view | show_project_search: false})}
  end

  def handle_cast({:set_file_nav_width, width}, state) do
    {:noreply, publish(state, %{state.view | file_nav_width: width})}
  end

  def handle_cast(:refresh_file_nav, state) do
    {:noreply,
     publish(state, %{state.view | file_nav_revision: state.view.file_nav_revision + 1})}
  end

  def handle_cast({:set_file_nav_path, path}, state) do
    new_view = %{
      state.view
      | file_nav_path: path,
        file_nav_revision: state.view.file_nav_revision + 1
    }

    {:noreply, publish(state, new_view)}
  end

  def handle_cast({:set_tab_width, n}, state) do
    {:noreply, publish(state, %{state.view | tab_width: n})}
  end

  def handle_cast({:set_text_size, n}, state) do
    {:noreply, publish(state, %{state.view | text_size: n})}
  end

  def handle_cast({:set_fold_level, n}, state) do
    {:noreply, publish(state, %{state.view | fold_level: n})}
  end

  def handle_cast({:set_theme, id}, state) do
    {:noreply, publish(state, %{state.view | theme: id})}
  end

  def handle_cast({:set_chrome_zoom, n}, state) do
    {:noreply, publish(state, %{state.view | chrome_zoom: n})}
  end

  def handle_cast({:show_status, message, severity}, state) do
    show_status_now(state, message, severity)
  end

  def handle_cast(
        {:show_action_feedback, _message},
        %{view: %{show_action_feedback: false}} = state
      ),
      do: {:noreply, state}

  def handle_cast({:show_action_feedback, message}, state) do
    show_status_now(state, message, :info)
  end

  defp show_status_now(state, message, severity) do
    ref = make_ref()
    Process.send_after(self(), {:clear_status, ref}, @status_clear_ms)

    state = publish(state, %{state.view | status_message: message, status_severity: severity})
    {:noreply, %{state | status_ref: ref}}
  end

  def handle_info({:clear_status, ref}, %{status_ref: ref} = state) do
    state = publish(state, %{state.view | status_message: nil})
    {:noreply, %{state | status_ref: nil}}
  end

  # A newer show_status re-stamped status_ref — this timer is stale, ignore it
  def handle_info({:clear_status, _stale_ref}, state), do: {:noreply, state}

  # ── Internals ──

  # The single commit point: every mutation publishes the full view map.
  defp publish(state, new_view) do
    Scenic.PubSub.publish(Sources.view(), new_view)
    %{state | view: new_view}
  end
end
