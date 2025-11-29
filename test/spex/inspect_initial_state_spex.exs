defmodule Quillex.InspectInitialStateSpex do
  @moduledoc """
  Just inspect what's in the app when it starts - no input sending.
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Initial State Inspection",
    description: "See what's rendered initially",
    tags: [:debug, :inspection] do

    scenario "Inspect initial render", context do
      given_ "app just started", context do
        IO.puts("\n=== INITIAL STATE INSPECTION ===")
        Process.sleep(1000)  # Let app fully initialize
        :ok
      end

      when_ "we check what's rendered", context do
        IO.puts("\n--- Script Table Inspection ---")
        vp_pid = Process.whereis(:main_viewport)
        vp_state = :sys.get_state(vp_pid)

        if vp_state.script_table do
          entries = :ets.tab2list(vp_state.script_table)
          IO.puts("Script table entries: #{length(entries)}")

          Enum.with_index(entries) |> Enum.each(fn {entry, idx} ->
            case entry do
              {id, script_data, _pid} ->
                IO.puts("\n  Entry #{idx}: #{inspect(id)}")
                if is_list(script_data) do
                  # Look for text operations
                  text_ops = Enum.filter(script_data, fn op ->
                    case op do
                      {:draw_text, _} -> true
                      {:draw_text, _, _} -> true
                      {:text, _} -> true
                      _ -> false
                    end
                  end)
                  if text_ops != [] do
                    IO.puts("    Text operations: #{inspect(text_ops)}")
                  end
                end
              {id, script_data} ->
                IO.puts("\n  Entry #{idx}: #{inspect(id)}")
                if is_list(script_data) do
                  text_ops = Enum.filter(script_data, fn op ->
                    case op do
                      {:draw_text, _} -> true
                      {:draw_text, _, _} -> true
                      {:text, _} -> true
                      _ -> false
                    end
                  end)
                  if text_ops != [] do
                    IO.puts("    Text operations: #{inspect(text_ops)}")
                  end
                end
              other ->
                IO.puts("\n  Entry #{idx}: Unknown format: #{inspect(other, limit: 5)}")
            end
          end)
        end

        IO.puts("\n--- ScriptInspector Output ---")
        rendered = ScriptInspector.extract_rendered_text()
        IO.puts("All rendered text: #{inspect(rendered)}")

        user_content = ScriptInspector.extract_user_content()
        IO.puts("User content (filtered): #{inspect(user_content)}")

        full = ScriptInspector.get_rendered_text_string()
        IO.puts("Full text string: '#{full}'")

        :ok
      end

      then_ "we understand the initial state", context do
        IO.puts("\nInspection complete")
        :ok
      end
    end
  end
end
