defmodule Quillex.TabVisualProbeSpex do
  @moduledoc "THROWAWAY: capture the tab drop indicator."
  use SexySpex

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticProbe

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_200)
    Quillex.TestHelpers.AppReset.reset!()

    bufs =
      for n <- ["alpha.ex", "beta.ex", "gamma.ex", "delta.ex"] do
        {:ok, b} = Quillex.Buffer.new(%{name: n, data: ["x"]})
        b
      end

    Process.sleep(800)
    {:ok, bufs: bufs}
  end

  defp centre(uuid) do
    %{entry: %{screen_bounds: b}} = SemanticProbe.dump("tab_bar_#{uuid}")
    {b.left + b.width / 2, b.top + b.height / 2}
  end

  defp tb do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :tab_bar)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid).assigns.state
  end

  defp widths(label) do
    s = tb()
    ws = Enum.map(s.tabs, fn t -> {t.label, Map.get(s.tab_widths, t.id)} end)
    IO.puts("#{label}: #{inspect(ws)}")
  end

  spex "tab drag visuals", description: "drop line", tags: [:probe] do
    scenario "capture mid-drag" do
      given_ "several tabs are open", context do
        Process.sleep(400)
        widths("IDLE")
        Probes.take_screenshot("probe_tabs_idle")
        {:ok, context}
      end

      when_ "the second tab is dragged toward the third", context do
        [_a, b, c, _d] = context.bufs
        {bx, by} = centre(b.uuid)
        {cx, _cy} = centre(c.uuid)

        Probes.mouse_down(bx, by)
        Process.sleep(120)
        Probes.send_mouse_move(bx + 40, by)
        Process.sleep(250)
        widths("DRAGGING")
        Probes.take_screenshot("probe_tabs_dragging")

        Probes.send_mouse_move(cx + 20, by)
        Process.sleep(250)
        widths("SWAPPED")
        Probes.take_screenshot("probe_tabs_swapped")

        Probes.mouse_up(cx + 20, by)
        Process.sleep(400)
        {:ok, context}
      end

      then_ "released", context do
        widths("RELEASED")
        Probes.take_screenshot("probe_tabs_released")
        {:ok, context}
      end
    end
  end
end
