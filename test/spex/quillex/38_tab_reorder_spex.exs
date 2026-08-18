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

    # Reordering worked before this, but silently: tabs simply teleported past
    # each other with nothing to say a drag was under way or where the tab would
    # end up.
    scenario "A drag in flight shows a drop line and lifts the tab" do
      given_ "no drag is happening", context do
        refute tab_bar_state().drag_active?
        refute drop_indicator_visible?()
        {:ok, Map.put(context, :centres, tab_centres(context))}
      end

      when_ "a tab is pressed but not yet moved", context do
        {fx, fy} = context.centres.first
        Probes.mouse_down(fx, fy)
        Process.sleep(150)

        # A press is not a drag. Every ordinary tab click starts this way, and
        # flashing the drop line on each one would be noise.
        refute tab_bar_state().drag_active?
        refute drop_indicator_visible?()
        {:ok, context}
      end

      when_ "the pointer travels far enough to count as a drag", context do
        {fx, fy} = context.centres.first
        Probes.send_mouse_move(fx + 30, fy)
        Process.sleep(200)
        {:ok, context}
      end

      then_ "the drop line marks the slot and the tab reads as lifted", context do
        state = tab_bar_state()
        assert state.drag_active?

        assert drop_indicator_visible?()

        # It straddles the leading edge of the dragged tab's slot.
        {slot_x, _y, _w, _h} =
          ScenicWidgets.TabBar.State.get_tab_bounds(state, state.dragging_tab_id)

        {drawn_x, _} = Scenic.Primitive.get_transform(drop_indicator(), :translate)
        assert_in_delta drawn_x + 1.5, slot_x, 0.01

        dragged_bg = tab_background(state.dragging_tab_id)
        assert dragged_bg == state.theme.tab_drag_background
        refute dragged_bg == state.theme.tab_selected_background

        {:ok, context}
      end

      then_ "releasing clears the feedback", context do
        {fx, fy} = context.centres.first
        Probes.mouse_up(fx + 30, fy)
        Process.sleep(300)

        refute tab_bar_state().drag_active?
        assert tab_bar_state().dragging_tab_id == nil
        refute drop_indicator_visible?()
        {:ok, context}
      end
    end
  end

  defp tab_bar_scene do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :tab_bar)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid)
  end

  defp tab_bar_state, do: tab_bar_scene().assigns.state
  defp tab_bar_graph, do: tab_bar_scene().assigns.graph

  defp drop_indicator do
    case Scenic.Graph.get(tab_bar_graph(), :tab_drop_indicator) do
      [primitive] -> primitive
      [] -> nil
    end
  end

  # The indicator is a permanent primitive painted :clear when idle — patching
  # one fill beats rebuilding the graph on every mouse-down — so "is it
  # showing?" is a question about colour, not about presence.
  defp drop_indicator_visible? do
    case drop_indicator() do
      nil ->
        false

      primitive ->
        case Scenic.Primitive.get_style(primitive, :fill) do
          {:color, {:color_rgba, {_r, _g, _b, 0}}} -> false
          nil -> false
          _ -> true
        end
    end
  end

  defp tab_background(tab_id) do
    [primitive] = Scenic.Graph.get(tab_bar_graph(), {:tab_bg, tab_id})

    case Scenic.Primitive.get_style(primitive, :fill) do
      {:color, {:color_rgba, {r, g, b, _a}}} -> {r, g, b}
      other -> other
    end
  end

  # Screen centres of the two fixture tabs, whatever order they are in now —
  # the previous scenario deliberately swapped them.
  defp tab_centres(context) do
    Map.new([first: context.first, second: context.second], fn {name, buffer} ->
      %{entry: %{screen_bounds: b}} = SemanticProbe.dump("tab_bar_#{buffer.uuid}")
      {name, {b.left + b.width / 2, b.top + b.height / 2}}
    end)
  end
end
