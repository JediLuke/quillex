defmodule Quillex.FileNavResizeSpex do
  @moduledoc """
  The file navigator divider can be dragged and remembers its width when a
  drag through the collapse threshold hides it.
  """
  use SexySpex

  alias ScenicMcp.Probes
  alias Quillex.RadixCache.ViewStore

  @top_bar_h 35

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(2000)
    Quillex.TestHelpers.AppReset.reset!()
    :ok
  end

  defp handle_y do
    root_state = :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state
    @top_bar_h + trunc((root_state.frame.size.height - @top_bar_h) * 0.9)
  end

  defp drag_handle(from_x, to_x, opts) do
    y = handle_y()
    Probes.send_mouse_move(from_x, y)
    Process.sleep(100)
    assert resize_bubble_fill() == {:color, {:color_rgba, {72, 91, 126, 255}}}

    Probes.mouse_down(from_x, y)
    Process.sleep(100)

    root_state = :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

    assert root_state.file_nav_resizing,
           "resize pill did not capture the press at #{inspect({from_x, y})}"

    assert resize_bubble_fill() == {:color, {:color_rgba, {205, 216, 236, 255}}}

    root_scene = :sys.get_state(Process.whereis(QuillEx.RootScene))
    assert {:ok, captures} = Scenic.Scene.fetch_captures(root_scene)
    assert :cursor_button in captures
    assert :cursor_pos in captures

    Probes.send_mouse_move(to_x, y)
    Process.sleep(150)

    if live_width = Keyword.get(opts, :live_width) do
      root_scene = :sys.get_state(Process.whereis(QuillEx.RootScene))
      {:ok, child} = Scenic.Scene.child(root_scene, :file_nav)
      nav_pid = if is_list(child), do: List.first(child), else: child
      nav_state = :sys.get_state(nav_pid).assigns.state

      assert nav_state.frame.size.width == live_width,
             "navigator did not resize during the captured drag"

      assert {:ok, captures} = Scenic.Scene.fetch_captures(root_scene)
      assert :cursor_button in captures
      assert :cursor_pos in captures
    end

    if Keyword.get(opts, :expect_collapse, false) do
      root_state = :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

      assert root_state.file_nav_resize_hide?,
             "dragging to #{to_x} did not enter the navigator collapse zone"
    end

    Probes.mouse_up(to_x, y)
    Process.sleep(700)

    root_state = :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state
    refute root_state.file_nav_resizing, "resize gesture did not receive mouse-up"

    unless Keyword.get(opts, :expect_collapse, false) do
      assert resize_bubble_fill() == {:color, {:color_rgba, {55, 60, 72, 255}}}
    end
  end

  defp resize_bubble_fill do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    [bubble] = Scenic.Graph.get(root.assigns.graph, :file_nav_resize_bubble)
    Scenic.Primitive.get_style(bubble, :fill)
  end

  spex "The file navigator divider resizes and collapses",
    description:
      "Dragging changes the stored width; crossing the thin threshold hides without forgetting it",
    tags: [:phase_31, :file_nav, :resize] do
    scenario "Dragging the divider wider resizes the navigator" do
      given_ "the navigator is open at a known width", context do
        ViewStore.set_file_nav_width(250)
        ViewStore.open_file_nav()
        ViewStore.sync()
        Process.sleep(700)

        root = :sys.get_state(Process.whereis(QuillEx.RootScene))
        {:ok, nav_pid} = Scenic.Scene.child(root, :file_nav)
        {:ok, pane_pid} = Scenic.Scene.child(root, :buffer_pane)

        for id <- [
              :file_nav_resize_arrow_shaft,
              :file_nav_resize_arrow_left_up,
              :file_nav_resize_arrow_left_down,
              :file_nav_resize_arrow_right_up,
              :file_nav_resize_arrow_right_down
            ] do
          assert [_line] = Scenic.Graph.get(root.assigns.graph, id)
        end

        {:ok, Map.merge(context, %{nav_pid: nav_pid, pane_pid: pane_pid})}
      end

      when_ "the resize pill is dragged to the right", context do
        drag_handle(250, 340, live_width: 340)
        {:ok, context}
      end

      then_ "the new width is committed to the view store", context do
        %{show_file_nav: visible?, file_nav_width: width} = ViewStore.get_state()
        assert visible?
        assert width == 340

        root = :sys.get_state(Process.whereis(QuillEx.RootScene))
        assert Scenic.Scene.child(root, :file_nav) == {:ok, context.nav_pid}
        assert Scenic.Scene.child(root, :buffer_pane) == {:ok, context.pane_pid}
        {:ok, context}
      end
    end

    scenario "Dragging through the collapse threshold hides but remembers width" do
      given_ "the widened navigator is visible", context do
        ViewStore.open_file_nav()
        ViewStore.sync()
        Process.sleep(500)
        %{file_nav_width: width} = ViewStore.get_state()
        {:ok, Map.put(context, :width, width)}
      end

      when_ "the resize pill is dragged almost closed", context do
        drag_handle(context.width, 80, expect_collapse: true)
        {:ok, context}
      end

      then_ "the navigator is hidden and its useful width is retained", context do
        %{show_file_nav: visible?, file_nav_width: width, status_message: status} =
          ViewStore.get_state()

        refute visible?
        assert width == context.width
        assert status == "File navigator hidden"
        {:ok, context}
      end
    end
  end
end
