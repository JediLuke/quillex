defmodule Quillex.OpenFilesSpex do
  @moduledoc """
  Opening files: a large prose document and a source file.

  Split out of `07_integration_v1_spex.exs` (roadmap Part II item 9).
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers
  import Quillex.TestHelpers.Integration

  setup_all do
    fresh_editor!()
    assert File.exists?(spinoza_path()), "fixture missing: #{spinoza_path()}"
    assert File.exists?(code_file_path()), "fixture missing: #{code_file_path()}"
    :ok
  end

  # SPEX 3: OPEN LARGE FILE (Spinoza's Ethics)
  # =========================================================================

  spex "V1 Integration - Open Large File",
    description: "Validates opening and viewing a large text file",
    tags: [:v1, :integration, :file_open, :scroll] do
    scenario "Open Spinoza's Ethics Part 1" do
      given_ "Spinoza's Ethics file exists", context do
        assert File.exists?(spinoza_path()), "Spinoza file not found at #{spinoza_path()}"
        {:ok, context}
      end

      when_ "we open the file", context do
        # Close any existing Spinoza buffer first, so this really opens a
        # FRESH copy from disk. File→Open deliberately activates an
        # already-open buffer rather than duplicating the tab (correct app
        # behaviour), which means a buffer edited by an earlier scenario
        # would otherwise be handed back here with its edits intact.
        close_buffer_named("spinozas_ethics_p1.txt")

        result = open_file(spinoza_path())
        Process.sleep(1000)
        {:ok, Map.put(context, :open_result, result)}
      end

      then_ "buffer should be named after the file", context do
        names = buffer_names()
        has_spinoza = Enum.any?(names, &String.contains?(&1, "spinozas_ethics"))

        assert has_spinoza,
               "Expected a buffer with 'spinozas_ethics' in #{inspect(names)}"

        {:ok, context}
      end

      then_ "buffer should contain the file content", context do
        # Switch to the Spinoza buffer (wait_for_tab_selected polls up to 2s)
        switch_to_buffer("spinozas_ethics_p1.txt")

        # Poll until the expected content appears — switching tab triggers a render cycle
        # that can take several frames before the semantic table reflects the new buffer.
        assert {:ok, content} = wait_for_content_containing("CONCERNING GOD", 5000),
               "Expected to find 'CONCERNING GOD' in Spinoza buffer within 5s. Last content: #{String.slice(active_buffer_content() || "", 0, 200)}"

        assert String.contains?(content, "DEFINITIONS"),
               "Expected to find 'DEFINITIONS' in content"

        {:ok, context}
      end
    end

    scenario "The whole document is loaded, not just what is on screen" do
      given_ "Spinoza's Ethics is open", context do
        switch_to_buffer("spinozas_ethics_p1.txt")
        Process.sleep(300)
        {:ok, context}
      end

      when_ "we ask the buffer how long it is", context do
        # NOT by counting lines in the semantic content: that is what the pane
        # RENDERS, which is a window of a few dozen lines around the viewport.
        # The old assertion counted them and expected 339, which held only
        # while some earlier scenario happened to have scrolled to the end.
        [buf] =
          Quillex.Buffer.list()
          |> Enum.filter(&(&1.name == "spinozas_ethics_p1.txt"))

        {:ok, snapshot} = Quillex.Buffer.fetch(buf)
        {:ok, Map.put(context, :line_count, length(snapshot.lines))}
      end

      then_ "it holds every line of the file", context do
        on_disk = spinoza_path() |> File.read!() |> String.split("\n") |> length()

        assert context.line_count in (on_disk - 1)..on_disk,
               "the buffer holds #{context.line_count} lines, the file has #{on_disk}"

        assert context.line_count in 339..340,
               "the fixture should be ~339 lines; got #{context.line_count}"

        {:ok, context}
      end
    end
  end

  # =========================================================================
  # SPEX 4: OPEN CODE FILE
  # =========================================================================

  spex "V1 Integration - Open Code File",
    description: "Validates opening an Elixir code file",
    tags: [:v1, :integration, :code_file] do
    scenario "Open app.ex" do
      given_ "app.ex exists", context do
        assert File.exists?(code_file_path()), "Code file not found at #{code_file_path()}"
        {:ok, context}
      end

      when_ "we open the file", context do
        open_file(code_file_path())
        Process.sleep(1000)
        {:ok, context}
      end

      then_ "buffer should be named 'app.ex'", context do
        names = buffer_names()
        assert "app.ex" in names, "Expected 'app.ex' in #{inspect(names)}"
        {:ok, context}
      end

      then_ "buffer should contain Elixir code", context do
        switch_to_buffer("app.ex")
        Process.sleep(300)

        assert {:ok, _content} = wait_for_content_containing("defmodule")

        {:ok, context}
      end
    end
  end

  # =========================================================================
end
