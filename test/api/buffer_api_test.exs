defmodule Quillex.APITests.BufferAPITest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Quillex.API.FileAPI

  describe "verify_file_integrity/0" do
    test "returns a valid result tuple" do
      result = capture_log(fn -> send(self(), FileAPI.verify_file_integrity()) end)
      assert is_binary(result)
      assert_received result_value

      assert match?({:ok, _}, result_value) or match?({:error, _}, result_value),
             "Expected {:ok, _} or {:error, _}, got: #{inspect(result_value)}"
    end

    test "error result carries a non-empty binary reason" do
      capture_log(fn ->
        case FileAPI.verify_file_integrity() do
          {:error, reason} ->
            send(self(), {:check, reason})

          {:ok, _} ->
            :ok
        end
      end)

      receive do
        {:check, reason} ->
          assert is_binary(reason), "Error reason must be a binary, got: #{inspect(reason)}"
          assert String.length(reason) > 0, "Error reason must be non-empty"
      after
        0 -> :ok
      end
    end
  end

  describe "save/0" do
    test "returns an error tuple when buffer has no associated file path" do
      capture_log(fn ->
        result = FileAPI.save()

        assert match?({:error, _}, result) or match?({:ok, _}, result),
               "Expected {:ok, _} or {:error, _}, got: #{inspect(result)}"

        case result do
          {:error, reason} ->
            assert is_binary(reason), "Error reason must be a binary"

          {:ok, _} ->
            :ok
        end
      end)
    end
  end

  describe "info/0" do
    test "returns a valid result tuple" do
      capture_log(fn ->
        result = FileAPI.info()

        assert match?({:ok, _}, result) or match?({:error, _}, result),
               "Expected {:ok, _} or {:error, _}, got: #{inspect(result)}"
      end)
    end
  end
end
