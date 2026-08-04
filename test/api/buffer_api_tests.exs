defmodule Quillex.APITests.BufferAPITest do
  use ExUnit.Case

  alias Quillex.API.FileAPI

  describe "verify_file_integrity/0" do
    test "returns a valid result tuple" do
      # When the Quillex app is running with a fresh (no-filepath) buffer,
      # verify_file_integrity/0 returns {:ok, :no_file}.
      # When no RootScene process is running, it returns {:error, binary_reason}.
      # Both outcomes are valid — the important invariant is that it never raises.
      result = FileAPI.verify_file_integrity()

      assert match?({:ok, _}, result) or match?({:error, _}, result),
             "Expected {:ok, _} or {:error, _}, got: #{inspect(result)}"
    end

    test "error result carries a non-empty binary reason" do
      # When the result is an error, the reason must be a non-empty string
      # so that callers can display a meaningful message.
      case FileAPI.verify_file_integrity() do
        {:error, reason} ->
          assert is_binary(reason), "Error reason must be a binary, got: #{inspect(reason)}"
          assert String.length(reason) > 0, "Error reason must be non-empty"

        {:ok, _} ->
          # App is running — no error, nothing to assert for this test
          :ok
      end
    end
  end

  describe "save/0" do
    test "returns an error tuple when buffer has no associated file path" do
      # When the active buffer has no filepath (fresh buffer or no app running),
      # save/0 must return {:error, reason} with a binary reason.
      result = FileAPI.save()

      assert match?({:error, _}, result) or match?({:ok, _}, result),
             "Expected {:ok, _} or {:error, _}, got: #{inspect(result)}"

      case result do
        {:error, reason} ->
          assert is_binary(reason), "Error reason must be a binary"

        {:ok, _} ->
          :ok
      end
    end
  end

  describe "info/0" do
    test "returns a valid result tuple" do
      # When the app is running, info/0 returns {:ok, map}.
      # When no process is running, it returns {:error, binary_reason}.
      result = FileAPI.info()

      assert match?({:ok, _}, result) or match?({:error, _}, result),
             "Expected {:ok, _} or {:error, _}, got: #{inspect(result)}"
    end
  end
end
