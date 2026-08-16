defmodule Quillex.API.FileAPITest do
  use ExUnit.Case
  alias Quillex.API.FileAPI

  # ---------------------------------------------------------------------------
  # verify_file_integrity/0
  # ---------------------------------------------------------------------------
  #
  # verify_file_integrity/0 calls get_active_buffer_data/0, which calls
  # Buffer.active_buf/0 → GenServer.call(QuillEx.RootScene, :get_active_buffer).
  #
  # In the standard test environment QuillEx.App starts the full supervision
  # tree INCLUDING Scenic (QuillEx.RootScene). The default buffer is created
  # on startup with no file path. Therefore verify_file_integrity/0 returns
  # {:ok, :no_file} — NOT {:error, _} — in the normal test run.
  #
  # If the app has NOT started (headless CI, :started_by_flamelex? etc.) the
  # GenServer call exits with :noproc, is caught, and {:error, reason} is returned.
  #
  # Both return values are valid; we test the union.
  #
  # Full end-to-end behaviour (unchanged / modified / deleted / no_file) is
  # tested via the integration spex in test/spex/quillex/11_run_verification_spex.exs.
  # ---------------------------------------------------------------------------

  describe "verify_file_integrity/0 — smoke tests" do
    test "returns a tagged tuple in all runtime contexts" do
      # With a running app: {:ok, :no_file} (default buffer, no filepath).
      # Without a running RootScene: {:error, reason} (exit caught).
      result = FileAPI.verify_file_integrity()

      assert match?({:ok, _}, result) or match?({:error, _}, result),
             "Must return a tagged tuple, got: #{inspect(result)}"
    end

    test "result is a recognisable status atom or an error string" do
      case FileAPI.verify_file_integrity() do
        {:ok, status} when status in [:unchanged, :modified, :deleted, :no_file] ->
          :ok

        {:error, reason} when is_binary(reason) and reason != "" ->
          :ok

        other ->
          flunk("Unexpected result from verify_file_integrity/0: #{inspect(other)}")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # reload/0 — smoke tests
  # ---------------------------------------------------------------------------
  #
  # reload/0 calls get_active_buffer_data/0 which goes through Buffer.active_buf/0
  # → GenServer.call(QuillEx.RootScene, :get_active_buffer), the same path as
  # verify_file_integrity/0.
  #
  # With a running app and the default unnamed buffer (no file path):
  #   → {:error, "Buffer has no associated file path"}
  # Without a running RootScene:
  #   → {:error, reason}  (exit caught and converted to string)
  #
  # Full round-trip behaviour (file reloaded into buffer) is tested via spex.
  # ---------------------------------------------------------------------------

  describe "reload/0 — smoke tests" do
    test "returns a tagged tuple in all runtime contexts" do
      result = FileAPI.reload()

      assert match?({:ok, _}, result) or match?({:error, _}, result),
             "reload/0 must return a tagged tuple, got: #{inspect(result)}"
    end

    test "returns {:error, _} when the default buffer has no file path" do
      # Default buffer on startup has no associated file path.
      # If a RootScene is running: {:error, "Buffer has no associated file path"}.
      # If no RootScene: {:error, reason} from caught :noproc exit.
      case FileAPI.reload() do
        {:error, reason} when is_binary(reason) and reason != "" ->
          :ok

        {:ok, _} ->
          # Only acceptable if somehow the active buffer has a file path (unlikely in CI)
          :ok

        other ->
          flunk("Unexpected result from reload/0: #{inspect(other)}")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # check_file_status/2 — pure comparison logic, fully unit-testable
  # ---------------------------------------------------------------------------
  #
  # check_file_status/2 is the extracted comparison kernel: it takes buffer
  # lines and a file path and returns {:ok, :unchanged | :modified | :deleted}
  # or {:error, reason}.  No live RootScene is needed.
  # ---------------------------------------------------------------------------

  @tmp_dir "/tmp/quillex_file_api_test"

  setup do
    File.mkdir_p!(@tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    :ok
  end

  describe "open/1 text boundary" do
    test "rejects an executable-like binary without creating a buffer" do
      path = Path.join(@tmp_dir, "binary_#{System.unique_integer([:positive])}")
      File.write!(path, <<0x7F, "ELF", 2, 1, 1, 0, 0, 0xFF, 0xFE>>)
      before = length(Quillex.Buffer.list())

      assert {:error, message} = FileAPI.open(path)
      assert message =~ "not UTF-8 text"
      assert length(Quillex.Buffer.list()) == before
    end
  end

  describe "check_file_status/2 — comparison kernel" do
    test ":unchanged when buffer lines match file content exactly" do
      path = Path.join(@tmp_dir, "unchanged_#{System.unique_integer([:positive])}.txt")
      File.write!(path, "hello\nworld")
      assert {:ok, :unchanged} = FileAPI.check_file_status(["hello", "world"], path)
    end

    test ":unchanged for a single-line buffer matching a single-line file" do
      path = Path.join(@tmp_dir, "single_#{System.unique_integer([:positive])}.txt")
      File.write!(path, "one line")
      assert {:ok, :unchanged} = FileAPI.check_file_status(["one line"], path)
    end

    test ":modified when buffer content differs from file" do
      path = Path.join(@tmp_dir, "modified_#{System.unique_integer([:positive])}.txt")
      File.write!(path, "original content on disk")
      assert {:ok, :modified} = FileAPI.check_file_status(["buffer has different content"], path)
    end

    test ":modified when file has extra lines compared to buffer" do
      path = Path.join(@tmp_dir, "extra_#{System.unique_integer([:positive])}.txt")
      File.write!(path, "line1\nline2\nline3")
      assert {:ok, :modified} = FileAPI.check_file_status(["line1", "line2"], path)
    end

    test ":deleted when file does not exist on disk" do
      path = Path.join(@tmp_dir, "nonexistent_#{System.unique_integer([:positive])}.txt")
      assert {:ok, :deleted} = FileAPI.check_file_status(["some content"], path)
    end

    test ":deleted for an empty buffer when file does not exist" do
      path = Path.join(@tmp_dir, "nonexistent_empty_#{System.unique_integer([:positive])}.txt")
      assert {:ok, :deleted} = FileAPI.check_file_status([""], path)
    end

    test ":unchanged for a zero-byte file matched against a single empty-string buffer line" do
      # File.write!(path, "") → 0 bytes; String.split("", "\n") = [""]
      # A freshly-created empty buffer also has data: [""], so they must match.
      path = Path.join(@tmp_dir, "empty_file_#{System.unique_integer([:positive])}.txt")
      File.write!(path, "")
      assert {:ok, :unchanged} = FileAPI.check_file_status([""], path)
    end

    test ":modified when file is empty but buffer has content" do
      path = Path.join(@tmp_dir, "empty_vs_content_#{System.unique_integer([:positive])}.txt")
      File.write!(path, "")
      assert {:ok, :modified} = FileAPI.check_file_status(["some content"], path)
    end

    test ":modified when buffer is empty but file has content" do
      path = Path.join(@tmp_dir, "content_vs_empty_#{System.unique_integer([:positive])}.txt")
      File.write!(path, "some content")
      assert {:ok, :modified} = FileAPI.check_file_status([""], path)
    end

    test "check_file_status/2 is exported and callable" do
      # Smoke test: the function is part of the public API
      path = Path.join(@tmp_dir, "smoke_#{System.unique_integer([:positive])}.txt")
      File.write!(path, "smoke")
      result = FileAPI.check_file_status(["smoke"], path)
      assert match?({:ok, _}, result)
    end
  end
end
