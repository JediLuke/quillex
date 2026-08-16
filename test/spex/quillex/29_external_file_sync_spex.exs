defmodule Quillex.ExternalFileSyncSpex do
  @moduledoc """
  End-to-end proof that an ordinary external disk write reaches the rendered
  editor without a manual Reload command.

  The scenario deliberately waits for the supervised poller instead of calling
  its test hook. It therefore covers file detection, buffer dispatch, retained
  snapshot publication, TextField update, and the transient status bar.
  """

  use SexySpex

  alias ScenicMcp.Query
  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(2_000)
    Quillex.TestHelpers.AppReset.reset!()
    :ok
  end

  spex "An open file reloads when changed on disk",
    description: "External writes update the rendered pane and show a reload status",
    tags: [:phase_29, :files, :external_sync] do
    scenario "A clean active file changes outside Quillex" do
      given_ "an open clean file with known content", context do
        path =
          Path.join(
            System.tmp_dir!(),
            "quillex_external_sync_spex_#{System.unique_integer([:positive])}.txt"
          )

        File.write!(path, "before_external_change")

        :ok = Quillex.TestHelpers.FileOpener.open_file(path)

        on_exit(fn ->
          Quillex.Buffer.list()
          |> Enum.find(&(&1.path == Path.expand(path)))
          |> case do
            nil -> :ok
            ref -> Quillex.Buffer.close(ref, :discard)
          end

          File.rm(path)
        end)

        assert wait_until(fn ->
                 ScriptInspector.rendered_text_contains?("before_external_change")
               end)

        {:ok, Map.put(context, :path, path)}
      end

      when_ "another program replaces the file contents", context do
        File.write!(context.path, "after_external_change")
        {:ok, context}
      end

      then_ "the pane and status bar update without a manual reload", context do
        assert wait_until(fn ->
                 ScriptInspector.rendered_text_contains?("after_external_change")
               end),
               "externally changed content never reached the rendered pane"

        refute ScriptInspector.rendered_text_contains?("before_external_change")

        assert Query.text_visible?("Reloaded #{Path.basename(context.path)} from disk"),
               "external reload status was not visible"

        {:ok, context}
      end
    end
  end

  defp wait_until(fun, attempts \\ 30)
  defp wait_until(_fun, 0), do: false

  defp wait_until(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(100)
      wait_until(fun, attempts - 1)
    end
  end
end
