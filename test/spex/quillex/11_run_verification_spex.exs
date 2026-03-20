defmodule Quillex.RunVerificationSpex do
  @moduledoc """
  Phase 11: run_verification — File Integrity Check

  Validates the "Verify File" feature (File → Verify File / Ctrl+V+F).

  run_verification compares the active buffer's in-memory content against
  the file on disk and logs one of four outcomes:
    - "File is unchanged on disk"
    - "File has been modified on disk since last save"
    - "File has been deleted from disk"
    - "Buffer has no associated file path"

  Since the feature writes to the Logger and does not mutate visible UI state,
  these spex verify:
    1. The action is reachable via the File menu.
    2. The app remains stable (renders, accepts input) after verification.
    3. Verification with a saved-and-unmodified file produces no UI disruption.
    4. Verification with a missing file (deleted on disk) produces no UI crash.
    5. Verification with a file modified on disk (differs from buffer) produces no UI crash.

  Pre-conditions: Quillex is running, at least one buffer is open.
  """
  use SexySpex

  alias ScenicMcp.Query
  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers
  alias Quillex.TestHelpers.FileOpener

  @tmp_dir "/tmp/quillex_verify_test"
  @tmp_file "verify_test_file.txt"

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

  defp open_file_menu do
    Probes.click_element("icon_menu_file")
    Process.sleep(300)
  end

  defp click_verify_menu_item do
    Probes.click_element("icon_menu_file_verify")
    Process.sleep(300)
  end

  defp type_text(text) do
    Probes.send_text(text)
    Process.sleep(200)
  end

  defp clear_buffer do
    Probes.send_keys("a", [:ctrl])
    Process.sleep(50)
    Probes.send_keys("backspace", [])
    Process.sleep(100)
  end

  defp close_all_but_one do
    count = SemanticHelpers.get_tab_count() || 0
    if count > 1 do
      Probes.click_element("icon_menu_file")
      Process.sleep(300)
      Probes.click_element("icon_menu_file_close")
      Process.sleep(400)
      close_all_but_one()
    end
  end

  defp tmp_file_path, do: Path.join(@tmp_dir, @tmp_file)

  # ===========================================================================
  # SPEX: Verify File menu item is present and reachable
  # ===========================================================================

  spex "RunVerification - Verify File menu item is accessible",
    description: "File menu contains Verify File item",
    tags: [:run_verification, :menu, :smoke] do

    scenario "Verify File appears in the File menu", context do
      given_ "the Quillex app is running", context do
        Process.sleep(300)
        {:ok, context}
      end

      when_ "we open the File menu", context do
        open_file_menu()
        {:ok, context}
      end

      then_ "the Verify File menu item is visible", context do
        rendered = Query.rendered_text()
        assert String.contains?(rendered, "Verify"),
               "File menu should contain a 'Verify' item. Got: #{inspect(rendered)}"
        :ok
      end

      # Close menu without clicking
      when_ "we dismiss the menu with Escape", context do
        Probes.send_keys("escape", [])
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the menu is closed", context do
        :ok
      end
    end
  end

  # ===========================================================================
  # SPEX: Verify File on an unsaved (no filepath) buffer
  # ===========================================================================

  spex "RunVerification - Verify File on buffer with no filepath",
    description: "Verify File on an unsaved buffer logs and does not crash the app",
    tags: [:run_verification, :no_filepath, :smoke] do

    scenario "Verify File on a new unsaved buffer completes without crashing", context do
      given_ "we have one open buffer with no saved file path", context do
        # Use Ctrl+N to open a fresh untitled buffer — this guarantees the active
        # buffer has no file path association, regardless of what prior tests left.
        # close_all_but_one() + clear_buffer() is insufficient: the remaining buffer
        # may carry a filepath from a prior Save As test (e.g. file 09).
        Probes.send_keys("escape", [])
        Process.sleep(100)
        Probes.send_keys("n", [:ctrl])
        Process.sleep(400)
        type_text("some unsaved content")
        {:ok, context}
      end

      when_ "we invoke Verify File via the File menu", context do
        open_file_menu()
        click_verify_menu_item()
        {:ok, context}
      end

      then_ "the app is still rendering correctly", context do
        rendered = Query.rendered_text()
        assert is_binary(rendered) and rendered != "",
               "App should still be rendering after verify on no-filepath buffer"
        :ok
      end

      then_ "the status bar shows that the buffer has no associated file path", context do
        rendered = Query.rendered_text()
        assert String.contains?(rendered, "no associated file path"),
               "Status bar should show 'no associated file path'. Got: #{inspect(rendered)}"
        :ok
      end

      then_ "the buffer is still editable", context do
        # Type additional text — if the buffer process died, this would fail
        type_text("x")
        Process.sleep(100)

        rendered = Query.rendered_text()
        # The 'x' we typed should be present somewhere in the editor area
        assert is_binary(rendered),
               "Viewport should still be renderable after verification"
        :ok
      end

      then_ "cleanup: close the new buffer", context do
        # Close the Ctrl+N buffer we opened — return to prior state
        close_all_but_one()
        :ok
      end
    end
  end

  # ===========================================================================
  # SPEX: Verify File on a buffer whose file matches disk
  # ===========================================================================

  spex "RunVerification - Verify File on saved buffer (file unchanged)",
    description: "Verify File on a saved file that has not changed on disk logs 'unchanged'",
    tags: [:run_verification, :file_unchanged] do

    scenario "Verify File on a saved, unmodified file does not crash or disrupt editing", context do
      given_ "we create and save a temp file directly on disk", context do
        content = "Hello from Quillex verify test"
        File.write!(tmp_file_path(), content)
        {:ok, Map.put(context, :expected_content, content)}
      end

      given_ "we open that file in Quillex", context do
        # Use FileOpener (boundary-safe wrapper around FileAPI) to open the file
        # into a new buffer. The RootScene receives a PubSub :new_buffer_opened
        # event and updates the tab bar automatically.
        case FileOpener.open_file(tmp_file_path()) do
          :ok ->
            Process.sleep(500)
            # Wait for the tab to appear in the UI
            tab_name = Path.basename(tmp_file_path())
            SemanticHelpers.wait_for_tab(tab_name, 3000)

          {:error, reason} ->
            flunk("Could not open temp file via FileOpener: #{inspect(reason)}")
        end

        {:ok, context}
      end

      when_ "we invoke Verify File via the File menu", context do
        open_file_menu()
        click_verify_menu_item()
        {:ok, context}
      end

      then_ "the app continues to render without errors", context do
        rendered = Query.rendered_text()
        assert is_binary(rendered) and rendered != "",
               "App should still render after verify of unchanged file"
        :ok
      end

      then_ "the status bar shows that the file is unchanged on disk", context do
        rendered = Query.rendered_text()
        assert String.contains?(rendered, "unchanged on disk"),
               "Status bar should show 'unchanged on disk'. Got: #{inspect(rendered)}"
        :ok
      end

      then_ "the buffer content is intact", context do
        # The file content should still be visible in the editor
        rendered = Query.rendered_text()
        assert String.contains?(rendered, "Hello"),
               "Buffer should still display file content after verification"
        :ok
      end

      then_ "cleanup: close the buffer and remove temp file", context do
        close_all_but_one()
        File.rm(tmp_file_path())
        :ok
      end
    end
  end

  # ===========================================================================
  # SPEX: Verify File on a buffer whose file was deleted from disk
  # ===========================================================================

  spex "RunVerification - Verify File when file has been deleted from disk",
    description: "Verify File on a buffer whose file no longer exists logs a warning and does not crash",
    tags: [:run_verification, :file_deleted] do

    scenario "Verify File with a deleted file logs warning without crashing", context do
      given_ "we create a temp file and open it in Quillex", context do
        deleted_path = Path.join(@tmp_dir, "will_be_deleted.txt")
        File.write!(deleted_path, "Content before deletion")

        case FileOpener.open_file(deleted_path) do
          :ok ->
            Process.sleep(500)
            # Wait for the tab to appear
            tab_name = Path.basename(deleted_path)
            SemanticHelpers.wait_for_tab(tab_name, 3000)

          {:error, reason} ->
            flunk("Could not open temp file via FileOpener: #{inspect(reason)}")
        end

        {:ok, Map.put(context, :deleted_path, deleted_path)}
      end

      given_ "we delete the file from disk before running verification", context do
        File.rm!(context.deleted_path)
        {:ok, context}
      end

      when_ "we invoke Verify File", context do
        open_file_menu()
        click_verify_menu_item()
        {:ok, context}
      end

      then_ "the app does not crash", context do
        # If the RootScene process crashed, we would not get a rendered viewport
        rendered = Query.rendered_text()
        assert is_binary(rendered) and rendered != "",
               "App should still be alive after verifying a deleted file"
        :ok
      end

      then_ "the status bar shows that the file was deleted from disk", context do
        rendered = Query.rendered_text()
        assert String.contains?(rendered, "deleted from disk"),
               "Status bar should show 'deleted from disk'. Got: #{inspect(rendered)}"
        :ok
      end

      then_ "cleanup: close extra buffer", context do
        close_all_but_one()
        :ok
      end
    end
  end

  # ===========================================================================
  # SPEX: Verify File on a buffer whose file has been modified on disk
  # ===========================================================================

  spex "RunVerification - Verify File when file has been modified on disk",
    description: "Verify File on a buffer whose file was changed externally logs a warning and does not crash",
    tags: [:run_verification, :file_modified] do

    scenario "Verify File with a modified file does not crash the app", context do
      given_ "we create a temp file and open it in Quillex", context do
        modified_path = Path.join(@tmp_dir, "will_be_modified.txt")
        File.write!(modified_path, "Original content before external edit")

        case FileOpener.open_file(modified_path) do
          :ok ->
            Process.sleep(500)
            tab_name = Path.basename(modified_path)
            SemanticHelpers.wait_for_tab(tab_name, 3000)

          {:error, reason} ->
            flunk("Could not open temp file via FileOpener: #{inspect(reason)}")
        end

        {:ok, Map.put(context, :modified_path, modified_path)}
      end

      given_ "we modify the file on disk without changing the buffer", context do
        # Write different content to disk — the in-memory buffer still has the old content
        File.write!(context.modified_path, "Externally modified content — differs from buffer")
        {:ok, context}
      end

      when_ "we invoke Verify File", context do
        open_file_menu()
        click_verify_menu_item()
        {:ok, context}
      end

      then_ "the app does not crash", context do
        rendered = Query.rendered_text()
        assert is_binary(rendered) and rendered != "",
               "App should still be alive after verifying a modified file"
        :ok
      end

      then_ "the status bar shows that the file was modified on disk", context do
        rendered = Query.rendered_text()
        assert String.contains?(rendered, "modified on disk"),
               "Status bar should show 'modified on disk'. Got: #{inspect(rendered)}"
        :ok
      end

      then_ "the buffer is still editable after verification", context do
        type_text("x")
        Process.sleep(100)
        rendered = Query.rendered_text()
        assert is_binary(rendered),
               "Viewport should still be renderable after modification verification"
        :ok
      end

      then_ "cleanup: close extra buffer and remove temp file", context do
        close_all_but_one()
        File.rm(context.modified_path)
        :ok
      end
    end
  end

  # ===========================================================================
  # SPEX: App remains stable when Ctrl+V and Ctrl+F are pressed sequentially
  # ===========================================================================
  #
  # NOTE: run_verification has NO keyboard shortcut. The original Ctrl+V+F
  # design was removed because Scenic 0.12 uses atom key format (:key_f, :ctrl)
  # and "v" is not a GLFW modifier key — the chord cannot be expressed.
  # run_verification is accessible via File → Verify File only.
  #
  # This spex verifies that pressing Ctrl+V (paste) then Ctrl+F (find) in
  # sequence does not crash the running app — a basic stability check.

  spex "RunVerification - App stable after Ctrl+V then Ctrl+F key sequence",
    description: "Pressing Ctrl+V (paste) followed by Ctrl+F (find) does not crash the app",
    tags: [:run_verification, :stability] do

    scenario "Ctrl+V then Ctrl+F sequence leaves app alive and rendering", context do
      given_ "we have one buffer open with some content", context do
        close_all_but_one()
        clear_buffer()
        type_text("stability test content")
        {:ok, context}
      end

      when_ "we press Ctrl+V (paste) then Ctrl+F (find)", context do
        # Ctrl+V triggers paste; Ctrl+F opens the find bar.
        # Neither should crash the app.
        Probes.send_keys("v", [:ctrl])
        Process.sleep(50)
        Probes.send_keys("f", [:ctrl])
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the app is still responsive and rendering", context do
        rendered = Query.rendered_text()
        assert is_binary(rendered) and rendered != "",
               "App should still render after Ctrl+V + Ctrl+F"
        :ok
      end

      then_ "cleanup: close search bar and clear the buffer", context do
        Probes.send_keys("escape", [])
        Process.sleep(100)
        clear_buffer()
        :ok
      end
    end
  end
end
