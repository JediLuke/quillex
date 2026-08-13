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
  """
  use GenServer

  alias Quillex.RadixCache.Sources

  @status_clear_ms 8_000
  @file_nav_width_range 160..800

  @initial %{
    # Editor settings (View menu toggles)
    show_line_numbers: true,
    word_wrap: false,
    tab_width: 4,
    text_size: 24,
    # File navigator sidebar
    show_file_nav: false,
    file_nav_path: nil,
    file_nav_width: 250,
    file_nav_revision: 0,
    # Search bar (flags owned here from Phase 6b)
    show_search_bar: false,
    show_replace: false,
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
  def toggle_word_wrap, do: GenServer.cast(__MODULE__, :toggle_word_wrap)
  def toggle_file_nav, do: GenServer.cast(__MODULE__, :toggle_file_nav)

  @doc "Show the file-navigator sidebar. Idempotent, unlike `toggle_file_nav/0`."
  def open_file_nav, do: GenServer.cast(__MODULE__, :open_file_nav)

  @doc "Close the file navigator. The counterpart to open_file_nav/0 — toggling is not the same thing when you need a known state."
  def close_file_nav, do: GenServer.cast(__MODULE__, :close_file_nav)

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

  def set_tab_width(n) when n in [2, 3, 4, 8] do
    GenServer.cast(__MODULE__, {:set_tab_width, n})
  end

  def set_text_size(n) when is_integer(n) and n in 12..32 do
    GenServer.cast(__MODULE__, {:set_text_size, n})
  end

  @doc "Show a transient status-bar message; the store clears it after eight seconds."
  def show_status(message, severity)
      when is_binary(message) and severity in [:info, :warning, :error] do
    GenServer.cast(__MODULE__, {:show_status, message, severity})
  end

  @doc """
  Synchronous heartbeat: returns after all casts queued before this call have
  been processed. Lets tests observe a burst of casts deterministically.
  """
  def sync, do: GenServer.call(__MODULE__, :sync)

  # ── GenServer ──

  def init(:ok) do
    Scenic.PubSub.register(Sources.view())
    view = %{@initial | file_nav_path: File.cwd!()}
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

  def handle_cast(:toggle_word_wrap, state) do
    {:noreply, publish(state, %{state.view | word_wrap: not state.view.word_wrap})}
  end

  def handle_cast(:toggle_file_nav, state) do
    {:noreply, publish(state, %{state.view | show_file_nav: not state.view.show_file_nav})}
  end

  def handle_cast(:close_file_nav, state) do
    {:noreply, publish(state, %{state.view | show_file_nav: false})}
  end

  def handle_cast(:open_file_nav, state) do
    {:noreply, publish(state, %{state.view | show_file_nav: true})}
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

  def handle_cast({:show_status, message, severity}, state) do
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
