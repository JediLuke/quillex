defmodule Quillex.TestHelpers.FileOpener do
  @moduledoc """
  Test helper for opening files programmatically in spex tests.

  Wraps `Quillex.API.FileAPI` to open a file into a new buffer.
  The FileAPI call triggers a PubSub `:new_buffer_opened` event which the
  RootScene handles — so the tab bar and buffer state are updated automatically.

  Use this instead of `GenServer.call(QuillEx.RootScene, {:action, {:open_file, path}})`
  which would violate the Quillex.Spex boundary.
  """

  @doc """
  Open a file in a new buffer.

  Reads the file at `path` and creates a new buffer with its contents.
  The RootScene will receive a `:new_buffer_opened` PubSub event and update
  the tab bar accordingly. Call `SemanticHelpers.wait_for_tab/1` afterwards
  to wait for the tab to appear.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  def open_file(path) when is_binary(path) do
    case Quillex.API.FileAPI.open(path) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
