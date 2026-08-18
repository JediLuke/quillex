defmodule Quillex.DragVisualProbeSpex do
  @moduledoc "THROWAWAY: capture the drag ghost and drop-target visuals."
  use SexySpex

  alias ScenicMcp.Probes
  alias Quillex.RadixCache.ViewStore

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
    end

    Process.sleep(1_500)
    Quillex.TestHelpers.AppReset.reset!()
    ViewStore.open_file_nav()
    ViewStore.sync()
    Process.sleep(800)
    :ok
  end

  defp nav_state do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :file_nav)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid).assigns.state
  end

  defp row_point(path) do
    s = nav_state()
    %{y: y, height: h} = Map.fetch!(s.item_bounds, path)
    {s.frame.pin.x + 40, s.frame.pin.y + y + h / 2 - s.scroll.offset_y}
  end

  defp pointer(action, {x, y}) do
    {:ok, vp} = Scenic.ViewPort.info(:main_viewport)
    Scenic.ViewPort.Input.send(vp, {:cursor_button, {:btn_left, action, [], {x, y}}})
  end

  defp move({x, y}) do
    {:ok, vp} = Scenic.ViewPort.info(:main_viewport)
    Scenic.ViewPort.Input.send(vp, {:cursor_pos, {x, y}})
  end

  spex "drag visuals", description: "ghost + drop target", tags: [:probe] do
    scenario "capture a drag in flight" do
      given_ "the navigator is showing the repo", context do
        cwd = File.cwd!()
        {:ok, Map.merge(context, %{lib: Path.join(cwd, "lib"), mix: Path.join(cwd, "mix.exs"), root: cwd})}
      end

      when_ "a file is dragged over a directory", context do
        from = row_point(context.mix)
        to = row_point(context.lib)
        pointer(1, from)
        Process.sleep(120)
        move(to)
        Process.sleep(80)
        move(to)
        Process.sleep(200)

        s = nav_state()
        IO.puts("VALID-DROP target=#{inspect(s.drag_target)} valid=#{inspect(s.drop_valid)} pos=#{inspect(s.drag_pos)}")
        Probes.take_screenshot("probe_drag_valid")
        {:ok, Map.merge(context, %{to: to})}
      end

      when_ "it hovers a file instead (invalid)", context do
        s = nav_state()

        bad_path =
          s.item_bounds
          |> Map.keys()
          |> Enum.filter(&(File.regular?(&1) and &1 != context.mix))
          |> Enum.sort_by(&Map.fetch!(s.item_bounds, &1).y)
          |> List.first()

        IO.puts("bad_path=#{inspect(bad_path)}")
        bad = row_point(bad_path)
        move(bad)
        Process.sleep(80)
        move(bad)
        Process.sleep(200)
        s = nav_state()
        IO.puts("INVALID-DROP target=#{inspect(s.drag_target)} valid=#{inspect(s.drop_valid)}")
        Probes.take_screenshot("probe_drag_invalid")
        {:ok, Map.put(context, :bad, bad)}
      end

      then_ "and over empty space (root)", context do
        s0 = nav_state()
        lowest = s0.item_bounds |> Map.values() |> Enum.map(&(&1.y + &1.height)) |> Enum.max()
        y = lowest - s0.scroll.offset_y + 30

        empty =
          if y < s0.frame.size.height - 10 do
            {s0.frame.pin.x + 40, s0.frame.pin.y + y}
          else
            IO.puts("(tree fills pane; skipping root-space capture)")
            nil
          end

        if empty do
          move(empty)
          Process.sleep(80)
          move(empty)
          Process.sleep(200)
          s = nav_state()
          IO.puts("ROOT-DROP target=#{inspect(s.drag_target)} valid=#{inspect(s.drop_valid)}")
          Probes.take_screenshot("probe_drag_root")
        end

        # Abandon the drag without moving anything.
        move(context.bad)
        Process.sleep(60)
        pointer(0, context.bad)
        Process.sleep(300)
        {:ok, context}
      end
    end
  end
end
