defmodule Quillex.UndoAndSaveSpex do
  @moduledoc """
  Edit history, and writing a buffer to disk and reading it back.

  Split out of `07_integration_v1_spex.exs` (roadmap Part II item 9).
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers
  import Quillex.TestHelpers.Integration

  setup_all do
    File.rm(temp_save_path())
    fresh_editor!()
    on_exit(fn -> File.rm(temp_save_path()) end)
    :ok
  end

  # SPEX 7: UNDO/REDO
  # =========================================================================

  spex "V1 Integration - Undo/Redo",
    description: "Validates undo and redo work correctly",
    tags: [:v1, :integration, :undo, :redo] do
    scenario "Undo restores previous state" do
      given_ "we have a fresh buffer with some text", context do
        new_empty_buffer()

        # Type some initial text
        Probes.send_text("Hello")
        Process.sleep(300)
        {:ok, _} = wait_for_active_buffer_content("Hello")
        content_before = active_buffer_content()

        assert content_before == "Hello",
               "Setup failed: expected 'Hello', got '#{content_before}'"

        {:ok, Map.put(context, :content_before, content_before)}
      end

      when_ "we type one more character and then undo", context do
        # Add just one character for simpler testing
        Probes.send_text("X")
        Process.sleep(300)
        {:ok, _} = wait_for_active_buffer_content("HelloX")
        content_with_addition = active_buffer_content()

        assert content_with_addition == "HelloX",
               "Add failed: expected 'HelloX', got '#{content_with_addition}'"

        # Single undo should remove the X (Ctrl+Z is undo)
        Probes.send_keys("z", [:ctrl])
        Process.sleep(300)
        {:ok, _} = wait_for_active_buffer_content("Hello")
        content_after_undo = active_buffer_content()

        {:ok,
         Map.merge(context, %{
           content_with_addition: content_with_addition,
           content_after_undo: content_after_undo
         })}
      end

      then_ "content should be restored", context do
        assert context.content_after_undo == context.content_before,
               "Undo should restore: expected '#{context.content_before}', got '#{context.content_after_undo}'"

        {:ok, context}
      end
    end

    scenario "Redo restores undone changes" do
      given_ "we set up fresh state for redo test", context do
        new_empty_buffer()

        Probes.send_text("Test")
        Process.sleep(300)
        Probes.send_text("Y")
        Process.sleep(300)
        {:ok, _} = wait_for_active_buffer_content("TestY")
        content_before_undo = active_buffer_content()

        # Undo (Ctrl+Z)
        Probes.send_keys("z", [:ctrl])
        Process.sleep(300)
        {:ok, _} = wait_for_active_buffer_content("Test")
        content_after_undo = active_buffer_content()

        {:ok,
         Map.merge(context, %{
           content_before_undo: content_before_undo,
           content_after_undo: content_after_undo
         })}
      end

      when_ "we redo", context do
        # Redo is Ctrl+Shift+Z
        Probes.send_keys("z", [:ctrl, :shift])
        Process.sleep(300)
        {:ok, _} = wait_for_active_buffer_content(context.content_before_undo)
        content_after_redo = active_buffer_content()
        {:ok, Map.put(context, :content_after_redo, content_after_redo)}
      end

      then_ "the undone text should be restored", context do
        assert context.content_after_redo == context.content_before_undo,
               "Redo should restore: expected '#{context.content_before_undo}', got '#{context.content_after_redo}'"

        {:ok, context}
      end
    end
  end

  # =========================================================================
  # SPEX 8: SAVE AND REOPEN
  # =========================================================================

  spex "V1 Integration - Save and Reopen",
    description: "Validates saving a file and reopening it preserves content",
    tags: [:v1, :integration, :save, :file_io] do
    scenario "Save buffer to temp file" do
      given_ "we have a buffer with unique content", context do
        new_empty_buffer()

        # Type unique content with timestamp
        unique_content = "Quillex v1.0 Test - #{:os.system_time(:second)}"
        Probes.send_text(unique_content)
        Process.sleep(300)
        {:ok, _} = wait_for_active_buffer_content(unique_content)

        {:ok, Map.put(context, :unique_content, unique_content)}
      end

      when_ "we save to a temp file", context do
        # Get active buffer content and save it
        content = active_buffer_content()

        if content do
          File.write!(temp_save_path(), content)
        end

        Process.sleep(500)
        {:ok, context}
      end

      then_ "file should exist with correct content", context do
        assert File.exists?(temp_save_path()), "Saved file should exist"
        file_content = File.read!(temp_save_path()) |> String.trim()

        assert file_content == context.unique_content,
               "File content should match: expected '#{context.unique_content}', got '#{file_content}'"

        {:ok, context}
      end
    end

    scenario "Close and reopen the saved file" do
      given_ "we have saved a file with unique content", context do
        new_empty_buffer()

        unique_content = "Reopen Test - #{:os.system_time(:second)}"
        Probes.send_text(unique_content)
        Process.sleep(300)
        {:ok, _} = wait_for_active_buffer_content(unique_content)

        # Save directly to temp file
        content = active_buffer_content()
        File.write!(temp_save_path(), content)
        Process.sleep(200)

        {:ok, Map.put(context, :unique_content, unique_content)}
      end

      when_ "we close and reopen it", context do
        # Close current buffer
        trigger_action(:close_active_buffer)
        Process.sleep(300)

        # Reopen the file
        open_file(temp_save_path())
        Process.sleep(500)
        {:ok, context}
      end

      then_ "content should match original", context do
        {:ok, _} = wait_for_active_buffer_content(context.unique_content)
        content = active_buffer_content()

        assert content == context.unique_content,
               "Reopened content should match: expected '#{context.unique_content}', got '#{content}'"

        # Cleanup
        File.rm(temp_save_path())
        {:ok, context}
      end
    end
  end

  # =========================================================================
end
