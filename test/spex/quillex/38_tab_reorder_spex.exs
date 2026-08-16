defmodule Quillex.TabReorderSpex do
  @moduledoc "Exercises real pointer-driven tab reordering and store persistence."
  use SexySpex

  alias Quillex.TestHelpers.{AppReset, SemanticProbe}
  alias ScenicMcp.Probes

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()
    {:ok, first} = Quillex.Buffer.new(%{name: "drag-first.ex", data: ["first"]})
    {:ok, second} = Quillex.Buffer.new(%{name: "drag-second.ex", data: ["second"]})
    Process.sleep(300)
    {:ok, first: first, second: second}
  end

  spex "Tabs can be reordered by dragging",
    description: "A real drag updates both the visible TabBar and BufferManager order",
    tags: [:phase_38, :tabs, :drag, :reorder] do
    scenario "Dragging the first tab past the second" do
      when_ "the first tab is pressed, moved across its neighbour, and released", context do
        %{entry: %{screen_bounds: first}} = SemanticProbe.dump("tab_bar_#{context.first.uuid}")
        %{entry: %{screen_bounds: second}} = SemanticProbe.dump("tab_bar_#{context.second.uuid}")
        from = {first.left + first.width / 2, first.top + first.height / 2}
        to = {second.left + second.width * 0.8, second.top + second.height / 2}

        Probes.mouse_down(elem(from, 0), elem(from, 1))
        Probes.send_mouse_move(elem(to, 0), elem(to, 1))
        Probes.mouse_up(elem(to, 0), elem(to, 1))
        Quillex.Buffer.BufferManager.sync()
        Process.sleep(250)
        {:ok, context}
      end

      then_ "the reordered tab list persists in the authoritative buffer store", context do
        ids = Quillex.Buffer.BufferManager.get_state().buffers |> Enum.map(& &1.uuid)

        assert Enum.find_index(ids, &(&1 == context.second.uuid)) <
                 Enum.find_index(ids, &(&1 == context.first.uuid))

        root = :sys.get_state(Process.whereis(QuillEx.RootScene))
        {:ok, child} = Scenic.Scene.child(root, :tab_bar)
        pid = if is_list(child), do: List.first(child), else: child
        visible_ids = :sys.get_state(pid).assigns.state.tabs |> Enum.map(& &1.id)
        assert visible_ids == ids
        {:ok, context}
      end
    end
  end
end
