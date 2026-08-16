defmodule Quillex.FoldingSpex do
  @moduledoc "Exercises folding through the assembled editor and real Scenic input."
  use SexySpex

  alias Quillex.TestHelpers.SemanticProbe
  alias ScenicMcp.Probes

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(1_500)
    Quillex.TestHelpers.AppReset.reset!()

    {:ok, ref} =
      Quillex.Buffer.new(%{
        name: "folding-spex.ex",
        data:
          [
            "defmodule FoldingSpex.Sample do",
            "  def one do",
            "    if true do",
            "      :one",
            "    end",
            "  def two do",
            "    :two",
            "  end",
            "end"
          ] ++ Enum.map(1..80, &"# trailing line #{&1}")
      })

    :ok = Quillex.Buffer.activate(ref)
    Process.sleep(700)
    :ok
  end

  defp text_field_scene do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :buffer_pane)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid)
  end

  defp state, do: text_field_scene().assigns.state
  defp graph, do: text_field_scene().assigns.graph

  spex "Folding is responsive and visible",
    description: "Menu levels and gutter triangles drive persistent TextField folds",
    tags: [:phase_35, :folding, :gutter] do
    scenario "A foldable line exposes a hover triangle and toggles from the gutter" do
      when_ "the pointer enters the first foldable line number", context do
        %{frame: frame} = state()
        Probes.send_mouse_move(frame.pin.x + 6, frame.pin.y + 8)
        Process.sleep(250)
        {:ok, context}
      end

      then_ "a downward fold affordance is rendered", context do
        assert state().fold_hover_line == 1
        assert Scenic.Graph.get(graph(), {:fold_toggle, 1}) != []
        {:ok, context}
      end

      when_ "the gutter affordance is clicked", context do
        %{frame: frame} = state()
        Probes.click(frame.pin.x + 6, frame.pin.y + 8)

        # No settling delay: the first wheel event after folding must be
        # accepted immediately rather than sitting behind the fold redraw.
        x = frame.pin.x + trunc(frame.size.width * 0.5)
        y = frame.pin.y + trunc(frame.size.height * 0.5)
        Probes.send_mouse_move(x, y)
        Probes.send_scroll(0, -1, x, y)
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the region folds and retains its line-count marker", context do
        assert MapSet.member?(state().folds, 1)
        assert Scenic.Graph.get(graph(), {:fold_toggle, 1}) != []
        assert state().scroll.offset_y > 0, "the immediate post-fold wheel event was delayed"

        rendered = Quillex.TestHelpers.ScriptInspector.get_rendered_text_flat()
        assert String.contains?(rendered, "lines")

        Probes.send_keys("home", [:ctrl])
        Process.sleep(150)
        {:ok, context}
      end

      when_ "the triangle is clicked again and the wheel is driven to the bottom", context do
        %{frame: frame} = state()
        folded_height = state().scroll.content_height

        center_x = frame.pin.x + trunc(frame.size.width * 0.5)
        center_y = frame.pin.y + trunc(frame.size.height * 0.5)
        Enum.each(1..20, fn _ -> Probes.send_scroll(0, 20, center_x, center_y) end)
        Process.sleep(150)
        assert state().scroll.offset_y == 0

        Probes.send_mouse_move(frame.pin.x + 6, frame.pin.y + 8)
        Process.sleep(100)
        assert state().fold_hover_line == 1
        Probes.click(frame.pin.x + 6, frame.pin.y + 8)
        Process.sleep(250)
        refute MapSet.member?(state().folds, 1)
        assert state().scroll.content_height > folded_height

        x = frame.pin.x + trunc(frame.size.width * 0.5)
        y = frame.pin.y + trunc(frame.size.height * 0.5)
        Probes.send_mouse_move(x, y)
        Enum.each(1..40, fn _ -> Probes.send_scroll(0, -20, x, y) end)
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the unfolded document can scroll all the way to its true end", context do
        scroll = state().scroll
        expected_bottom = max(scroll.content_height - scroll.viewport_height, 0)

        assert scroll.offset_y == expected_bottom,
               "wheel stopped at #{scroll.offset_y}, expected document bottom #{expected_bottom}"

        {:ok, context}
      end
    end

    scenario "Fold to Level 2 folds exactly the visible second-level headers" do
      when_ "Fold to Level 2 is selected from View", context do
        # The previous scenario deliberately leaves the viewport at the true
        # document bottom. Return to the fold headers before asserting their
        # virtualised gutter primitives.
        Probes.send_keys("home", [:ctrl])
        %{frame: frame} = state()
        center_x = frame.pin.x + trunc(frame.size.width * 0.5)
        center_y = frame.pin.y + trunc(frame.size.height * 0.5)
        Enum.each(1..40, fn _ -> Probes.send_scroll(0, 20, center_x, center_y) end)
        Process.sleep(200)
        assert state().scroll.offset_y == 0
        Probes.click_element("icon_menu_view")
        Process.sleep(150)

        %{entry: %{screen_bounds: bounds}} =
          SemanticProbe.dump(:icon_menu_view_fold_level)

        x = bounds.left + bounds.width - 24
        Probes.click(x, bounds.top + bounds.height / 2)
        Process.sleep(100)

        # The reusable Select expands inline. Level 2 is the second option
        # beneath its 28px control row.
        Probes.click(x, bounds.top + 28 + 28 * 1.5)
        Process.sleep(350)
        {:ok, context}
      end

      then_ "both level-2 headers remain visible with collapsed triangles", context do
        assert state().folds == MapSet.new([2, 6])
        assert Quillex.RadixCache.ViewStore.get_state().fold_level == 2
        assert Scenic.Graph.get(graph(), {:fold_toggle, 2}) != []
        assert Scenic.Graph.get(graph(), {:fold_toggle, 6}) != []
        {:ok, context}
      end
    end
  end
end
