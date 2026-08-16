defmodule Quillex.BufferViewRestoreSpex do
  @moduledoc "Exercises per-buffer viewport restoration through real tab clicks."
  use SexySpex

  alias Quillex.TestHelpers.SemanticHelpers
  alias ScenicMcp.Probes

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(1_500)
    Quillex.TestHelpers.AppReset.reset!()

    {:ok, first} =
      Quillex.Buffer.new(%{
        name: "view-a.txt",
        data: Enum.map(1..200, &"A line #{&1}")
      })

    {:ok, second} =
      Quillex.Buffer.new(%{
        name: "view-b.txt",
        data: Enum.map(1..200, &"B line #{&1}")
      })

    assert {:ok, _} = SemanticHelpers.wait_for_tab("view-a.txt")
    assert {:ok, _} = SemanticHelpers.wait_for_tab("view-b.txt")
    :ok = Quillex.Buffer.activate(first)
    Process.sleep(300)

    {:ok, first: first, second: second}
  end

  defp pane_state do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :buffer_pane)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid).assigns.state
  end

  defp scroll_down(notches) do
    frame = pane_state().frame
    x = frame.pin.x + trunc(frame.size.width / 2)
    y = frame.pin.y + trunc(frame.size.height / 2)
    Probes.send_mouse_move(x, y)
    Probes.send_scroll(0, -notches, x, y)
    Process.sleep(250)
    pane_state().scroll.offset_y
  end

  defp click_tab(label) do
    assert {:ok, _} = SemanticHelpers.click_tab_by_label(label)
    assert {:ok, _} = SemanticHelpers.wait_for_tab_selected(label)
    Process.sleep(250)
  end

  spex "Each buffer retains an independent viewport",
    description: "Wheel offsets survive real tab activation without moving the text cursor",
    tags: [:phase_36, :buffers, :scroll, :tabs] do
    scenario "Two scrolled tabs restore their own offsets" do
      when_ "the first tab is scrolled and the second tab is given a different offset", context do
        first_offset = scroll_down(6)
        assert first_offset > 0

        pane_store = :sys.get_state(Quillex.RadixCache.PaneStore)
        assert pane_store.buffer_uuid == context.first.uuid
        assert pane_store.views[context.first.uuid].offset_y == first_offset

        click_tab("view-b.txt")
        assert pane_state().scroll.offset_y == 0
        second_offset = scroll_down(12)
        assert second_offset > first_offset

        {:ok, Map.merge(context, %{first_offset: first_offset, second_offset: second_offset})}
      end

      then_ "each real tab click restores that tab's exact viewport", context do
        click_tab("view-a.txt")
        pane_store = :sys.get_state(Quillex.RadixCache.PaneStore)
        assert pane_store.buffer_uuid == context.first.uuid
        assert pane_store.views[context.first.uuid].offset_y == context.first_offset

        assert Scenic.PubSub.get(Quillex.RadixCache.PaneStore.source()).pane_view.offset_y ==
                 context.first_offset

        assert pane_state().scroll.offset_y == context.first_offset

        click_tab("view-b.txt")
        assert pane_state().scroll.offset_y == context.second_offset
        {:ok, context}
      end
    end
  end
end
