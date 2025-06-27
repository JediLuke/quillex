# defmodule QuillEx.Utils.Screenshot do
#   @moduledoc """
#   Screenshot utilities for capturing the current state of the Quillex application.
#   """

#   require Logger

#   @doc """
#   Take a screenshot of the current application state and save it to the specified path.

#   ## Parameters
#   - `path`: The file path where the screenshot should be saved (should end with .png)

#   ## Returns
#   - `:ok` on success
#   - `{:error, reason}` on failure

#   ## Examples

#       iex> QuillEx.Utils.Screenshot.take("/tmp/quillex_screenshot.png")
#       :ok

#       iex> QuillEx.Utils.Screenshot.take_timestamped("/tmp")
#       :ok
#   """
#   @spec take(String.t()) :: :ok | {:error, term()}
#   def take(path) when is_binary(path) do
#     try do
#       # Get the scenic driver process
#       case get_scenic_driver() do
#         {:ok, driver_pid} ->
#           Scenic.Driver.Local.screenshot(driver_pid, path)
#           Logger.info("Screenshot saved to: #{path}")
#           :ok

#         {:error, reason} ->
#           Logger.error("Failed to get scenic driver: #{inspect(reason)}")
#           {:error, reason}
#       end
#     rescue
#       error ->
#         Logger.error("Screenshot failed: #{inspect(error)}")
#         {:error, error}
#     end
#   end

#   @doc """
#   Take a timestamped screenshot in the specified directory.

#   ## Parameters
#   - `dir`: Directory where the screenshot should be saved (defaults to "/tmp")

#   ## Returns
#   - `{:ok, path}` with the path of the saved screenshot on success
#   - `{:error, reason}` on failure
#   """
#   @spec take_timestamped(String.t()) :: {:ok, String.t()} | {:error, term()}
#   def take_timestamped(dir \\ "/tmp") do
#     timestamp = DateTime.utc_now() |> DateTime.to_string() |> String.replace(~r/[:\s]/, "_")
#     filename = "quillex_screenshot_#{timestamp}.png"
#     path = Path.join(dir, filename)

#     case take(path) do
#       :ok -> {:ok, path}
#       error -> error
#     end
#   end

#   # Private function to get the scenic driver process
#   defp get_scenic_driver do
#     try do
#       # Look for the scenic driver in the supervision tree
#       case Process.whereis(:main_viewport) do
#         nil ->
#           {:error, :no_main_viewport}

#         viewport_pid ->
#           # Get the driver PIDs from the viewport state
#           viewport_state = :sys.get_state(viewport_pid)
#           case viewport_state.driver_pids do
#             [driver_pid | _] ->
#               {:ok, driver_pid}

#             [] ->
#               {:error, :no_driver_pids}
#           end
#       end
#     rescue
#       error ->
#         {:error, error}
#     end
#   end
# end
