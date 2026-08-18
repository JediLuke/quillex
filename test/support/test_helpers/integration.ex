defmodule Quillex.TestHelpers.Integration do
  @moduledoc """
  The shared vocabulary of the integration spex: open a file, switch tabs, read
  what the editor is actually showing, wait for it to settle.

  These lived inside `07_integration_v1_spex.exs`, the single file that held
  every integration scenario. That file failed a *different, shifting* set of
  scenarios on identical code, because its scenarios inherited each other's
  buffers and it assumed a near-boot state — so a real regression and ordinary
  noise looked exactly alike. Splitting it into per-feature files, each owning
  its own setup, is what made it a usable signal again (roadmap Part II item 9).

  Everything here reads through the semantic viewport rather than through
  `:sys.get_state`: what these scenarios are checking is what a user can see.
  """

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers

  @project_root Path.expand("../../..", __DIR__)

  @doc "Spinoza's Ethics — the large-file fixture."
  def spinoza_path, do: Path.join(@project_root, "biblio/spinozas_ethics_p1.txt")

  @doc "A source file, for the scenarios that want code rather than prose."
  def code_file_path, do: Path.join(@project_root, "lib/app.ex")

  @doc "Scratch file for the save/reopen round trip."
  def temp_save_path, do: "/tmp/quillex_v1_test_save.txt"

  @doc """
  A known starting point: the app running, the layout reset, and exactly one
  empty buffer.

  Every spex file that uses these helpers begins here. That is the whole point
  of the split — a scenario that inherits whatever the previous file left open
  fails for reasons that have nothing to do with what it is testing.
  """
  def fresh_editor! do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(1_500)
    Quillex.TestHelpers.AppReset.reset!()
    Process.sleep(400)
    close_search_bar_if_open()
    ensure_editor_focused()
    :ok
  end

  # Trigger action via UI interactions (boundary-compliant: no direct RootScene calls)
  def trigger_action(:close_active_buffer) do
    Probes.click_element("icon_menu_file")
    Process.sleep(200)
    Probes.click_element("icon_menu_file_close")
    Process.sleep(400)
    # If the buffer was dirty, a dialog appeared — discard changes and close.
    if ScenicMcp.Query.text_visible?("Unsaved Changes") do
      Probes.send_keys("d", [])
      Process.sleep(400)
    end
  end

  def trigger_action({:open_file, path}) when is_binary(path) do
    Quillex.TestHelpers.FileOpener.open_file(path)
  end

  def trigger_action({:activate_buffer, n}) when is_integer(n) do
    labels = buffer_names()

    case Enum.at(labels, n - 1) do
      nil -> :error
      label -> SemanticHelpers.click_tab_by_label(label)
    end
  end

  def trigger_action(:toggle_word_wrap) do
    Probes.click_element("icon_menu_view")
    Process.sleep(200)
    Probes.click_element("icon_menu_view_word_wrap")
    Process.sleep(300)
  end

  def trigger_action(:new_buffer) do
    Probes.click_element("icon_menu_file")
    Process.sleep(250)
    Probes.click_element("icon_menu_file_new")
    Process.sleep(500)
    ensure_editor_focused()
    wait_for_empty_buffer(2_000)
  end

  # Poll until the active buffer reads empty twice in a row (one read can
  # report "" for a document whose semantic entry is merely late).
  def wait_for_empty_buffer(timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_empty_buffer(deadline)
  end

  def do_wait_for_empty_buffer(deadline) do
    if (active_buffer_content() || "") == "" do
      Process.sleep(150)
      (active_buffer_content() || "") == ""
    else
      if System.monotonic_time(:millisecond) >= deadline do
        false
      else
        Process.sleep(150)
        do_wait_for_empty_buffer(deadline)
      end
    end
  end

  # Click into the pane (semantic frame → works at any window size) so the
  # editor owns keyboard focus. The "rotating" 07 failures traced to typed
  # setup text silently going nowhere when focus was left elsewhere.
  def ensure_editor_focused, do: ensure_editor_focused(3)

  def ensure_editor_focused(0) do
    raise """
    the editor pane never took keyboard focus.

    Every scenario that types depends on this, and when it silently fails the
    symptom is a keystroke that "did nothing" several steps later — which is
    what made the old integration spex so hard to read.
    """
  end

  def ensure_editor_focused(attempts) do
    %{x: x, y: y, width: w, height: h} = buffer_pane_frame()

    Probes.click(x + trunc(w * 0.4), y + trunc(h * 0.4))
    Process.sleep(200)

    # Assert the postcondition rather than assume the click landed. A click can
    # be swallowed by an overlay that is still closing, or by a pane being
    # rebuilt — and a click that did not take focus is indistinguishable from
    # one that did until the next keystroke goes nowhere.
    if editor_focused?() do
      :ok
    else
      Probes.send_keys("escape", [])
      Process.sleep(150)
      ensure_editor_focused(attempts - 1)
    end
  end

  @doc "Does the buffer pane hold the keyboard right now?"
  def editor_focused? do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))

    case Scenic.Scene.child(root, :buffer_pane) do
      {:ok, [pid | _]} ->
        state = :sys.get_state(pid, 30_000).assigns.state
        state.focused and not state.overlay_open

      _ ->
        false
    end
  end

  # The MAIN editor pane's frame, not "the latest text_buffer" — the search
  # pane and other components publish text_buffer entries too, and clicking a
  # frame that belongs to one of those focuses the wrong thing.
  defp buffer_pane_frame do
    {:ok, viewport} = Scenic.ViewPort.info(:main_viewport)

    {:ok, entries} = SemanticHelpers.find_by_type_all_graphs(viewport, :text_buffer)

    case Enum.find(entries, &(get_in(&1, [:semantic, :field_id]) == :buffer_pane)) do
      %{semantic: %{frame: %{x: _, y: _, width: _, height: _} = frame}} ->
        frame

      _ ->
        raise "no :buffer_pane entry in the semantic viewport — the editor is not on screen"
    end
  end

  # UI-based: Get tab count from semantic viewport
  def buffer_count do
    SemanticHelpers.get_tab_count() || 0
  end

  # UI-based: Get tab labels from semantic viewport
  def buffer_names do
    SemanticHelpers.get_tab_labels()
  end

  # UI-based: Get selected tab label from semantic viewport
  def active_buffer_name do
    SemanticHelpers.get_selected_tab_label()
  end

  # UI-based: get buffer_id from semantic metadata (no sys.get_state needed)
  def active_buffer_id do
    case Scenic.ViewPort.info(:main_viewport) do
      {:ok, viewport} ->
        case SemanticHelpers.find_text_buffer(viewport) do
          {:ok, buffer} -> get_in(buffer, [:semantic, :buffer_id])
          _ -> nil
        end

      _ ->
        nil
    end
  end

  def active_buffer_content do
    with {:ok, viewport} <- Scenic.ViewPort.info(:main_viewport) do
      # Prefer the MAIN EDITOR PANE's entry (field_id :buffer_pane). The
      # by-id / "latest text_buffer" lookups can return another component's
      # or a stale entry, which reads as "my text never arrived".
      pane_entry =
        case SemanticHelpers.find_by_type_all_graphs(viewport, :text_buffer) do
          {:ok, entries} ->
            Enum.find(entries, &(get_in(&1, [:semantic, :field_id]) == :buffer_pane))

          _ ->
            nil
        end

      if pane_entry do
        pane_entry.content || ""
      else
        buffer_id = active_buffer_id()

        lookup =
          if buffer_id do
            SemanticHelpers.find_text_buffer(viewport, buffer_id)
          else
            SemanticHelpers.find_text_buffer(viewport)
          end

        case lookup do
          {:ok, buffer} -> buffer.content || ""
          _ -> nil
        end
      end
    end
  end

  def active_buffer_semantic do
    with {:ok, viewport} <- Scenic.ViewPort.info(:main_viewport) do
      buffer_id = active_buffer_id()

      if buffer_id do
        SemanticHelpers.find_buffer_selection(viewport, buffer_id)
      else
        SemanticHelpers.find_buffer_selection(viewport)
      end
    end
  end

  def wait_for_active_buffer_content(expected, timeout \\ 5000) do
    with {:ok, viewport} <- Scenic.ViewPort.info(:main_viewport) do
      buffer_id = active_buffer_id()

      if buffer_id do
        SemanticHelpers.wait_for_buffer_content(viewport, expected, buffer_id, timeout)
      else
        SemanticHelpers.wait_for_buffer_content(viewport, expected, timeout)
      end
    end
  end

  def wait_for_active_selection(timeout \\ 2000) do
    SemanticHelpers.wait_for_active_selection(timeout)
  end

  def normalize_selection(%{start: start_pos, end: end_pos}) do
    if start_pos <= end_pos, do: {start_pos, end_pos}, else: {end_pos, start_pos}
  end

  def selected_text_from_line(line, selection) do
    {{start_line, start_col}, {end_line, end_col}} = normalize_selection(selection)

    if start_line != end_line do
      ""
    else
      String.slice(line, start_col - 1, end_col - start_col)
    end
  end

  # Get scroll offset from semantic viewport (UI-based)
  def get_scroll_offset do
    SemanticHelpers.get_scroll_offset()
  end

  # Poll active buffer content until it contains `text`, or until timeout.
  # Falls back to returning {:error, last_content} on timeout.
  def wait_for_content_containing(text, timeout_ms \\ 5000) do
    end_time = System.monotonic_time(:millisecond) + timeout_ms
    poll_content_containing(text, end_time)
  end

  def poll_content_containing(text, end_time) do
    content = active_buffer_content()

    cond do
      content != nil and String.contains?(content, text) ->
        {:ok, content}

      System.monotonic_time(:millisecond) >= end_time ->
        {:error, content}

      true ->
        Process.sleep(100)
        poll_content_containing(text, end_time)
    end
  end

  def close_all_but_one_buffer do
    close_buffers_loop()
  end

  def close_buffers_loop do
    if buffer_count() > 1 do
      trigger_action(:close_active_buffer)
      Process.sleep(200)
      close_buffers_loop()
    end
  end

  def open_file(path) do
    trigger_action({:open_file, path})
  end

  # Close a buffer by tab label, if it is open (discarding any edits). Used to
  # guarantee a genuinely fresh open in scenarios that assert on file content.
  def close_buffer_named(name) do
    if Enum.any?(buffer_names(), &String.contains?(&1, name)) do
      switch_to_buffer(name)
      Process.sleep(200)
      trigger_action(:close_active_buffer)
      Process.sleep(300)
    end
  end

  def send_mouse_click(x, y) do
    # Send mouse click via ScenicMcp
    ScenicMcp.Probes.click(x, y)
  end

  # Close search bar if open (via escape key - UI-based approach)
  def close_search_bar_if_open do
    # Send Escape twice to ensure we close any modal/search bar
    Probes.send_keys("escape", [])
    Process.sleep(100)
    Probes.send_keys("escape", [])
    Process.sleep(200)
  end

  # Switch to buffer by name using semantic tab info.
  # Retries the tab activation: the click can be lost if it lands while the
  # top bar is being recreated, and every scenario downstream of a failed
  # switch then asserts against the wrong buffer.
  def switch_to_buffer(name) do
    labels = buffer_names()
    index = Enum.find_index(labels, &(&1 == name))

    if index do
      trigger_action({:activate_buffer, index + 1})
      Process.sleep(300)
      match?({:ok, _}, SemanticHelpers.wait_for_tab_selected(name, 2000))
    else
      false
    end
  end

  # Activate the last buffer in the tab bar
  def activate_latest_buffer do
    labels = buffer_names()
    count = length(labels)

    if count > 0 do
      trigger_action({:activate_buffer, count})
      Process.sleep(300)
      List.last(labels)
    else
      nil
    end
  end

  @doc """
  A focused, genuinely empty buffer — the starting point for any scenario that
  types.

  This resets the editor rather than adding a tab and clearing it. Adding one
  is what the original did, and it is why `07` failed the way it did: File→New
  deliberately hands back an existing untitled buffer rather than duplicating
  it, so a scenario that had already typed into one got that text back, and its
  very first assertion failed with the *previous* scenario's content. The reset
  costs a fraction of a second and removes a whole class of failure.
  """
  def new_empty_buffer do
    Quillex.TestHelpers.AppReset.reset!()
    Process.sleep(400)

    close_search_bar_if_open()
    ensure_editor_focused()

    Probes.send_keys("a", [:ctrl])
    Process.sleep(100)
    Probes.send_keys("backspace", [])
    Process.sleep(250)

    wait_for_active_buffer_content("")
  end

end
