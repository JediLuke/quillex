defmodule Quillex.FileNavOperationsSpex do
  @moduledoc """
  The assembled file navigator keeps three ideas deliberately separate:

  * blue `active_id` follows the active editor buffer;
  * neutral `selected_ids` are the files an operation will affect;
  * expanded directories survive live tree refreshes.

  These spex also drive modifier clicks, drag-to-move, and the right-click
  delete confirmation through Scenic's real viewport input path. The disk is
  the assertion boundary: a convincing highlight is not enough if the file
  operation itself did not happen.
  """
  use SexySpex

  alias Quillex.Buffer.BufferManager
  alias Quillex.Files.NavigatorTreeSync
  alias Quillex.RadixCache.ViewStore
  alias Quillex.TestHelpers.SemanticProbe

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(1_500)
    Quillex.TestHelpers.AppReset.reset!()

    root = Path.join(System.tmp_dir!(), "quillex_nav_spex_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "destination"))
    File.mkdir_p!(Path.join(root, "opened"))
    File.write!(Path.join(root, "alpha.txt"), "alpha")
    File.write!(Path.join(root, "beta.txt"), "beta")
    File.write!(Path.join(root, "gamma.txt"), "gamma")
    File.write!(Path.join(root, "opened/child.txt"), "child")

    on_exit(fn -> File.rm_rf(root) end)

    ViewStore.set_file_nav_path(root)
    ViewStore.open_file_nav()
    ViewStore.sync()
    Process.sleep(700)

    {:ok, root: root}
  end

  defp nav_scene do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :file_nav)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid)
  end

  defp nav_state, do: nav_scene().assigns.state

  defp row_background(path) do
    [primitive] = Scenic.Graph.get(nav_scene().assigns.graph, String.to_atom("item_bg_#{path}"))

    case Scenic.Primitive.get_style(primitive, :fill) do
      {:color, {:color_rgba, {r, g, b, _alpha}}} -> {r, g, b}
      color -> color
    end
  end

  defp root_state do
    :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state
  end

  defp row_center(path) do
    id = String.to_atom("row_#{path}")

    %{entry: %{screen_bounds: %{left: left, top: top, width: width, height: height}}} =
      SemanticProbe.dump(id)

    # SideNav publishes child-local row bounds in this Scenic version. Project
    # them through the component frame before injecting viewport input.
    frame = nav_state().frame

    {frame.pin.x + left + min(width / 2, 100), frame.pin.y + top + height / 2}
  end

  defp pointer(button, action, mods, {x, y}) do
    {:ok, viewport} = Scenic.ViewPort.info(:main_viewport)
    Scenic.ViewPort.Input.send(viewport, {:cursor_button, {button, action, mods, {x, y}}})
  end

  defp click(path, mods \\ []) do
    point = row_center(path)
    pointer(:btn_left, 1, mods, point)
    pointer(:btn_left, 0, mods, point)
    Process.sleep(350)
  end

  defp right_click(path) do
    point = row_center(path)
    pointer(:btn_right, 1, [], point)
    pointer(:btn_right, 0, [], point)
    Process.sleep(250)
  end

  defp drag(source, target) do
    from = row_center(source)
    to = row_center(target)
    pointer(:btn_left, 1, [], from)
    Process.sleep(100)
    assert nav_state().drag_source == source
    {:ok, viewport} = Scenic.ViewPort.info(:main_viewport)
    Scenic.ViewPort.Input.send(viewport, {:cursor_pos, to})
    Process.sleep(100)
    state = nav_state()
    assert state.dragging

    local_target = {elem(to, 0) - state.frame.pin.x, elem(to, 1) - state.frame.pin.y}
    assert {^target, _region} = ScenicWidgets.SideNav.State.hit_test(state, local_target)

    pointer(:btn_left, 0, [], to)
    Process.sleep(500)
    assert nav_state().drag_source == nil
  end

  defp refresh_tree do
    NavigatorTreeSync.poll_now()
    ViewStore.sync()
    Process.sleep(500)
  end

  spex "Navigator selection and filesystem operations",
    description: "Active, selected, and expanded state stay distinct while the tree changes",
    tags: [:phase_33, :file_nav, :selection, :filesystem] do
    scenario "Active buffer is blue-state while Ctrl/Shift build neutral operation selection" do
      given_ "three files are visible", context do
        {:ok,
         Map.merge(context, %{
           alpha: Path.join(context.root, "alpha.txt"),
           beta: Path.join(context.root, "beta.txt"),
           gamma: Path.join(context.root, "gamma.txt")
         })}
      end

      when_ "one file is opened and another is Ctrl-selected", context do
        click(context.alpha)
        BufferManager.sync()
        Process.sleep(300)
        click(context.beta, [:ctrl])
        {:ok, context}
      end

      then_ "blue active state remains on the open buffer while selection contains both",
            context do
        state = nav_state()
        assert state.active_id == context.alpha
        assert state.selected_ids == MapSet.new([context.alpha, context.beta])
        assert row_background(context.alpha) == {60, 80, 120}
        assert row_background(context.beta) == {48, 51, 62}

        active = BufferManager.get_state().active_buf
        assert active.path == context.alpha
        {:ok, context}
      end

      when_ "Shift extends from the Ctrl-click anchor", context do
        click(context.gamma, [:shift])
        {:ok, context}
      end

      then_ "only the operation range changes; the active buffer does not", context do
        state = nav_state()
        assert state.active_id == context.alpha
        assert state.selected_ids == MapSet.new([context.beta, context.gamma])
        {:ok, context}
      end
    end

    scenario "Live disk refresh preserves expansion and selection" do
      given_ "a directory is expanded and a file selected", context do
        opened = Path.join(context.root, "opened")
        alpha = Path.join(context.root, "alpha.txt")
        click(opened)
        click(alpha, [:ctrl])
        assert MapSet.member?(nav_state().expanded, opened)
        {:ok, Map.merge(context, %{opened: opened, alpha: alpha})}
      end

      when_ "a new file appears on disk", context do
        fresh = Path.join(context.opened, "fresh.txt")
        File.write!(fresh, "fresh")
        refresh_tree()
        {:ok, Map.put(context, :fresh, fresh)}
      end

      then_ "the open tree updates without losing expansion or selection", context do
        state = nav_state()
        assert Map.has_key?(state.item_bounds, context.fresh)
        assert MapSet.member?(state.expanded, context.opened)
        assert MapSet.member?(state.selected_ids, context.alpha)
        {:ok, context}
      end
    end

    scenario "Selected files drag into a directory" do
      given_ "two files are selected for an operation", context do
        alpha = Path.join(context.root, "alpha.txt")
        beta = Path.join(context.root, "beta.txt")
        destination = Path.join(context.root, "destination")
        # Start from a known single selection; prior scenarios deliberately
        # leave a range selected to prove live refresh preserves it.
        click(destination)
        click(alpha)
        click(beta, [:ctrl])
        {:ok, Map.merge(context, %{alpha: alpha, beta: beta, destination: destination})}
      end

      when_ "the selection is dragged onto a directory", context do
        drag(context.alpha, context.destination)
        refresh_tree()
        {:ok, context}
      end

      then_ "both selected files have moved on disk", context do
        assert String.starts_with?(ViewStore.get_state().status_message, "Moved"),
               "drop produced status #{inspect(ViewStore.get_state().status_message)}; selection #{inspect(nav_state().selected_ids)}"

        refute File.exists?(context.alpha)
        refute File.exists?(context.beta)
        assert File.regular?(Path.join(context.destination, "alpha.txt"))
        assert File.regular?(Path.join(context.destination, "beta.txt"))
        {:ok, context}
      end
    end

    scenario "Right-click delete is confirmed before touching disk" do
      given_ "a disposable file is visible", context do
        doomed = Path.join(context.root, "doomed.txt")
        File.write!(doomed, "doomed")
        refresh_tree()
        {:ok, Map.put(context, :doomed, doomed)}
      end

      when_ "Delete is chosen from its context menu", context do
        right_click(context.doomed)

        ScenicMcp.Probes.send_keys("escape", [])
        Process.sleep(200)
        assert nav_state().context_menu == nil

        right_click(context.doomed)
        %{frame: frame} = nav_state()
        ScenicMcp.Probes.send_mouse_move(frame.pin.x + frame.size.width - 5, frame.pin.y + 5)
        Process.sleep(200)
        assert nav_state().context_menu == nil

        right_click(context.doomed)
        %{context_menu: %{x: x, y: y}, frame: frame} = nav_state()
        pointer(:btn_left, 1, [], {frame.pin.x + x + 30, frame.pin.y + y + 15})
        pointer(:btn_left, 0, [], {frame.pin.x + x + 30, frame.pin.y + y + 15})
        Process.sleep(300)
        {:ok, context}
      end

      then_ "a confirmation is shown and the file still exists", context do
        assert root_state().show_nav_delete_prompt
        assert File.regular?(context.doomed)
        {:ok, context}
      end

      when_ "the destructive action is confirmed", context do
        ScenicMcp.Probes.send_keys("d", [])
        Process.sleep(500)
        refresh_tree()
        {:ok, context}
      end

      then_ "the file is removed and the prompt closes", context do
        refute File.exists?(context.doomed)
        refute root_state().show_nav_delete_prompt
        {:ok, context}
      end
    end
  end
end
