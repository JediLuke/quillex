defmodule Quillex.UnsavedClosePromptSpex do
  @moduledoc """
  Phase 16: Unsaved-Changes Confirmation Dialog

  Validates the full close-buffer workflow when a buffer has unsaved changes.
  When the user tries to close a dirty buffer (Ctrl+W or tab close button),
  a ConfirmDialog appears with three choices:

    - Save    (S key)    — write buffer to disk, then close
    - Discard (D key)    — close without saving (changes lost)
    - Cancel  (Escape)   — leave buffer open with changes intact

  Scenarios covered:
    1. Dirty buffer shows dialog on Ctrl+W
    2. Clean buffer closes immediately on Ctrl+W (no dialog)
    3. Discard closes buffer without saving
    4. Cancel keeps buffer open with content intact
    5. Save saves then closes (file-backed buffer)
    6. Tab close button on dirty buffer shows dialog
  """
  use SexySpex

  alias ScenicMcp.Query
  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers
  alias Quillex.TestHelpers.FileOpener

  @tmp_dir "/tmp/quillex_close_prompt_test"

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    File.mkdir_p!(@tmp_dir)
    Process.sleep(2000)
    :ok
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp type_text(text) do
    Probes.send_text(text)
    Process.sleep(200)
  end

  # Close all tabs except the last one, discarding any unsaved-changes dialogs
  # that appear along the way.  Safe to call regardless of dirty state.
  defp force_close_all_but_one do
    count = SemanticHelpers.get_tab_count() || 0

    if count > 1 do
      Probes.click_element("icon_menu_file")
      Process.sleep(300)
      Probes.click_element("icon_menu_file_close")
      Process.sleep(400)

      # If the buffer was dirty, a dialog will have appeared — discard it.
      if Query.text_visible?("Unsaved Changes") do
        Probes.send_keys("d", [])
        Process.sleep(400)
      end

      force_close_all_but_one()
    end
  end

  defp tmp_file_path(name), do: Path.join(@tmp_dir, name)

  # ===========================================================================
  # SPEX 1: Dirty buffer shows dialog on Ctrl+W
  # ===========================================================================

  spex "UnsavedClosePrompt - Ctrl+W on dirty buffer shows confirmation dialog",
    description: "Pressing Ctrl+W with unsaved changes shows the unsaved-changes dialog",
    tags: [:unsaved_close_prompt, :ctrl_w, :dirty] do

    scenario "Ctrl+W on a dirty buffer shows the confirmation dialog" do
      given_ "the app is open with a single clean buffer", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)
        force_close_all_but_one()
        Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        Probes.send_keys("backspace", [])
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we type text to make the buffer dirty", context do
        type_text("hello dirty")
        {:ok, context}
      end

      when_ "we press Ctrl+W", context do
        Probes.send_keys("w", [:ctrl])
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the confirmation dialog is visible with the expected title" do
        rendered = Query.rendered_text()
        assert String.contains?(rendered, "Unsaved Changes"),
               "Dialog title 'Unsaved Changes' should be visible. Got: #{inspect(rendered)}"
        :ok
      end

      then_ "the dialog shows Save, Discard, and Cancel buttons" do
        rendered = Query.rendered_text()
        assert String.contains?(rendered, "Save"),
               "Dialog should show 'Save' button. Got: #{inspect(rendered)}"
        assert String.contains?(rendered, "Discard"),
               "Dialog should show 'Discard' button. Got: #{inspect(rendered)}"
        assert String.contains?(rendered, "Cancel"),
               "Dialog should show 'Cancel' button. Got: #{inspect(rendered)}"
        :ok
      end

      then_ "the buffer tab is still present while dialog is shown" do
        count = SemanticHelpers.get_tab_count() || 0
        assert count >= 1,
               "Buffer tab should still be present while dialog is shown. Tab count: #{count}"
        :ok
      end

      then_ "cleanup: dismiss dialog with Escape" do
        # Leave clean state for subsequent tests — Escape cancels without closing
        Probes.send_keys("escape", [])
        Process.sleep(400)
        :ok
      end
    end
  end

  # ===========================================================================
  # SPEX 1b: Stale-cache regression — dirty flip happens inside Buffer.Process
  # only, with no intervening RootScene action that would refresh its cached
  # BufRef. RootScene must consult the live buffer (not its stale dirty? cache)
  # when deciding whether to show the unsaved-changes dialog on Ctrl+W.
  # ===========================================================================

  spex "UnsavedClosePrompt - Ctrl+W on file-backed buffer with stale RootScene cache",
    description: "Ctrl+W shows dialog even when dirty flag was set only inside Buffer.Process (stale cache regression)",
    tags: [:unsaved_close_prompt, :ctrl_w, :dirty, :regression, :stale_cache] do

    scenario "Ctrl+W shows dialog even when dirty flag was set only inside Buffer.Process (stale cache regression)" do
      given_ "the app is open and other tabs are closed", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)
        force_close_all_but_one()
        {:ok, context}
      end

      given_ "a file-backed buffer is open (buffer_backed mode, TextField writes to Buffer.Process)", context do
        stale_file = tmp_file_path("stale_cache_regression.txt")
        File.write!(stale_file, "original content\n")

        case FileOpener.open_file(stale_file) do
          :ok ->
            Process.sleep(500)
            tab_name = Path.basename(stale_file)
            SemanticHelpers.wait_for_tab(tab_name, 3000)

          {:error, reason} ->
            flunk("Could not open temp file via FileOpener: #{inspect(reason)}")
        end

        {:ok, Map.put(context, :stale_file, stale_file)}
      end

      when_ "we type directly into the buffer (dirties Buffer.Process; RootScene cache stays stale)", context do
        # Direct typing through TextField → Buffer.Process. RootScene is not
        # subscribed to {:buffers, uuid} PubSub, so its cached BufRef remains
        # dirty?: false. We deliberately do NOT switch tabs, save, or open a
        # menu before pressing Ctrl+W — those would refresh RootScene's cache
        # and mask the regression.
        type_text("stale cache regression")
        {:ok, context}
      end

      when_ "we press Ctrl+W with no intervening RootScene action", context do
        Probes.send_keys("w", [:ctrl])
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the unsaved-changes dialog is visible" do
        rendered = Query.rendered_text()
        assert String.contains?(rendered, "Unsaved Changes"),
               "Dialog must appear even though only Buffer.Process knew the buffer was dirty. Got: #{inspect(rendered)}"
        :ok
      end

      then_ "the file-backed tab is still present while dialog is shown" do
        count = SemanticHelpers.get_tab_count() || 0
        assert count >= 1,
               "File-backed tab should still be present while dialog is shown. Tab count: #{count}"
        :ok
      end

      then_ "cleanup: discard the dirty buffer and remove temp file", context do
        # Dialog is open — pressing D discards changes and closes the buffer
        Probes.send_keys("d", [])
        Process.sleep(500)

        # Defensive: if the dialog somehow remained, escape it so subsequent
        # spex don't inherit a modal.
        if Query.text_visible?("Unsaved Changes") do
          Probes.send_keys("escape", [])
          Process.sleep(300)
        end

        File.rm(context.stale_file)
        {:ok, context}
      end
    end
  end

  # ===========================================================================
  # SPEX 2: Clean buffer closes immediately on Ctrl+W
  # ===========================================================================

  spex "UnsavedClosePrompt - Ctrl+W on clean buffer closes immediately",
    description: "A clean (unmodified) buffer closes without showing any dialog",
    tags: [:unsaved_close_prompt, :ctrl_w, :clean] do

    scenario "Ctrl+W on a clean new buffer closes without dialog" do
      given_ "we open a fresh clean buffer with Ctrl+N", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)
        initial_count = SemanticHelpers.get_tab_count() || 1

        Probes.send_keys("n", [:ctrl])
        Process.sleep(400)

        case SemanticHelpers.wait_for_tab_count(initial_count + 1, 3000) do
          {:ok, _} -> :ok
          {:error, reason} -> flunk("Ctrl+N did not open a new tab: #{inspect(reason)}")
        end

        new_count = SemanticHelpers.get_tab_count() || 0
        {:ok, Map.put(context, :count_before_close, new_count)}
      end

      when_ "we press Ctrl+W to close the clean buffer", context do
        Probes.send_keys("w", [:ctrl])
        Process.sleep(500)
        {:ok, context}
      end

      then_ "no confirmation dialog appears" do
        rendered = Query.rendered_text()
        refute String.contains?(rendered, "Unsaved Changes"),
               "Dialog should NOT appear for a clean buffer. Got: #{inspect(rendered)}"
        :ok
      end

      then_ "the tab count decreases by one", context do
        count = SemanticHelpers.get_tab_count() || 0
        expected = context.count_before_close - 1
        assert count == expected,
               "Tab count should be #{expected} after clean close, got #{count}"
        {:ok, context}
      end
    end
  end

  # ===========================================================================
  # SPEX 3: Discard closes buffer without saving
  # ===========================================================================

  spex "UnsavedClosePrompt - Discard closes buffer without saving",
    description: "Pressing D (discard) in the dialog closes the buffer without saving",
    tags: [:unsaved_close_prompt, :discard] do

    scenario "Discard on the unsaved-changes dialog removes the tab" do
      given_ "we have a dirty buffer open alongside an existing tab", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)
        # Open a second buffer so closing the dirty one leaves at least one tab
        Probes.send_keys("n", [:ctrl])
        Process.sleep(400)
        type_text("discard test content")
        count_before = SemanticHelpers.get_tab_count() || 1
        {:ok, Map.put(context, :count_before, count_before)}
      end

      when_ "we press Ctrl+W to trigger the dialog", context do
        Probes.send_keys("w", [:ctrl])
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the dialog is visible" do
        assert Query.text_visible?("Unsaved Changes"),
               "Unsaved changes dialog should be visible before discard"
        :ok
      end

      when_ "we press D to discard the changes", context do
        Probes.send_keys("d", [])
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the dialog disappears" do
        rendered = Query.rendered_text()
        refute String.contains?(rendered, "Unsaved Changes"),
               "Dialog should have closed after discard. Got: #{inspect(rendered)}"
        :ok
      end

      then_ "the buffer tab is removed from the tab bar", context do
        count = SemanticHelpers.get_tab_count() || 0
        expected = context.count_before - 1
        assert count == expected,
               "Tab count should drop to #{expected} after discard. Got: #{count}"
        {:ok, context}
      end
    end
  end

  # ===========================================================================
  # SPEX 4: Cancel keeps buffer open
  # ===========================================================================

  spex "UnsavedClosePrompt - Cancel keeps buffer open with content intact",
    description: "Pressing Escape (cancel) in the dialog keeps the buffer open",
    tags: [:unsaved_close_prompt, :cancel] do

    scenario "Cancel on the unsaved-changes dialog leaves the buffer intact" do
      given_ "we have a dirty buffer open", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)
        # Open a fresh buffer so the cancel test doesn't close the last tab
        Probes.send_keys("n", [:ctrl])
        Process.sleep(400)
        type_text("cancel test content")
        count = SemanticHelpers.get_tab_count() || 1
        {:ok, Map.put(context, :tab_count, count)}
      end

      when_ "we press Ctrl+W to trigger the dialog", context do
        Probes.send_keys("w", [:ctrl])
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the dialog is visible" do
        assert Query.text_visible?("Unsaved Changes"),
               "Unsaved changes dialog should be visible"
        :ok
      end

      when_ "we press Escape to cancel", context do
        Probes.send_keys("escape", [])
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the dialog disappears" do
        rendered = Query.rendered_text()
        refute String.contains?(rendered, "Unsaved Changes"),
               "Dialog should close after cancel. Got: #{inspect(rendered)}"
        :ok
      end

      then_ "the buffer tab count is unchanged", context do
        count = SemanticHelpers.get_tab_count() || 0
        assert count == context.tab_count,
               "Tab count should remain #{context.tab_count} after cancel. Got: #{count}"
        {:ok, context}
      end

      then_ "the buffer content is still visible" do
        rendered = Query.rendered_text()
        assert String.contains?(rendered, "cancel test content"),
               "Buffer content should still contain typed text after cancel. Got: #{inspect(rendered)}"
        :ok
      end

      then_ "cleanup: force-discard the dirty buffer" do
        Probes.send_keys("w", [:ctrl])
        Process.sleep(400)

        if Query.text_visible?("Unsaved Changes") do
          Probes.send_keys("d", [])
          Process.sleep(400)
        end

        :ok
      end
    end
  end

  # ===========================================================================
  # SPEX 5: Save saves then closes (file-backed buffer)
  # ===========================================================================

  spex "UnsavedClosePrompt - Save action saves changes and closes the buffer",
    description: "Pressing S (save) in the dialog writes changes to disk and removes the tab",
    tags: [:unsaved_close_prompt, :save, :file] do

    scenario "Save on unsaved-changes dialog saves file on disk and removes tab" do
      given_ "a temp file exists and is open in Quillex", context do
        save_file = tmp_file_path("save_then_close.txt")
        File.write!(save_file, "original content")

        case FileOpener.open_file(save_file) do
          :ok ->
            Process.sleep(500)
            tab_name = Path.basename(save_file)
            SemanticHelpers.wait_for_tab(tab_name, 3000)

          {:error, reason} ->
            flunk("Could not open temp file via FileOpener: #{inspect(reason)}")
        end

        {:ok, Map.put(context, :save_file, save_file)}
      end

      given_ "we edit the buffer to make it dirty", context do
        Probes.send_keys("end", [])
        Process.sleep(50)
        type_text(" — edited")
        count_before = SemanticHelpers.get_tab_count() || 1
        {:ok, Map.put(context, :count_before, count_before)}
      end

      when_ "we press Ctrl+W to trigger the dialog", context do
        Probes.send_keys("w", [:ctrl])
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the dialog is visible for the file-backed buffer" do
        assert Query.text_visible?("Unsaved Changes"),
               "Unsaved changes dialog should appear for edited file buffer"
        :ok
      end

      when_ "we press S to save", context do
        Probes.send_keys("s", [])
        # Allow time for file write and tab removal
        Process.sleep(800)
        {:ok, context}
      end

      then_ "the dialog disappears" do
        rendered = Query.rendered_text()
        refute String.contains?(rendered, "Unsaved Changes"),
               "Dialog should close after save. Got: #{inspect(rendered)}"
        :ok
      end

      then_ "the buffer tab is removed", context do
        count = SemanticHelpers.get_tab_count() || 0
        expected = context.count_before - 1
        assert count == expected,
               "Tab count should drop to #{expected} after save-and-close. Got: #{count}"
        {:ok, context}
      end

      then_ "the file on disk contains the updated content", context do
        disk_content = File.read!(context.save_file)
        assert String.contains?(disk_content, "edited"),
               "File on disk should have updated content after save. Got: #{inspect(disk_content)}"
        {:ok, context}
      end

      then_ "cleanup: remove temp file", context do
        File.rm(context.save_file)
        {:ok, context}
      end
    end
  end

  # ===========================================================================
  # SPEX 6: Tab close button on dirty buffer shows dialog
  # ===========================================================================

  spex "UnsavedClosePrompt - Tab close button on dirty buffer shows dialog",
    description: "Clicking the × close button on a dirty tab shows the confirmation dialog",
    tags: [:unsaved_close_prompt, :tab_button, :dirty] do

    scenario "Tab close button triggers the unsaved-changes dialog" do
      given_ "we have a base tab and a second dirty tab open", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)
        force_close_all_but_one()

        # Open a second tab and make it dirty
        Probes.send_keys("n", [:ctrl])
        Process.sleep(400)
        type_text("tab close button test")

        # Capture the UUID of the selected (dirty) tab for direct close-button click
        tab_id = SemanticHelpers.get_selected_tab_id()

        if is_nil(tab_id) do
          flunk("Could not get selected tab ID — tab bar not found")
        end

        {:ok, Map.put(context, :dirty_tab_id, tab_id)}
      end

      when_ "we click the close button on the dirty tab", context do
        # Construct the semantic ID for the close button using the tab UUID.
        # This avoids label-collision issues when multiple tabs share the same
        # "untitled" label.
        close_id = "tab_bar_close_#{context.dirty_tab_id}"
        Probes.click_element(close_id)
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the confirmation dialog appears" do
        rendered = Query.rendered_text()
        assert String.contains?(rendered, "Unsaved Changes"),
               "Dialog should appear when closing dirty tab via close button. Got: #{inspect(rendered)}"
        :ok
      end

      then_ "the dirty tab is still present in the tab bar" do
        count = SemanticHelpers.get_tab_count() || 0
        assert count >= 2,
               "Both tabs should still be present while dialog is shown. Tab count: #{count}"
        :ok
      end

      then_ "cleanup: discard to close the dirty buffer" do
        Probes.send_keys("d", [])
        Process.sleep(400)
        :ok
      end
    end
  end
end
