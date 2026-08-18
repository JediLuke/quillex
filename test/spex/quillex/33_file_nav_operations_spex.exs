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
    File.mkdir_p!(Path.join(root, "nest/inner"))
    File.write!(Path.join(root, "alpha.txt"), "alpha")
    File.write!(Path.join(root, "beta.txt"), "beta")
    File.write!(Path.join(root, "gamma.txt"), "gamma")
    File.write!(Path.join(root, "opened/child.txt"), "child")
    File.write!(Path.join(root, "nest/inner/deep.txt"), "deep")

    # Spex share one running app. Pointing the navigator at a temp directory and
    # then deleting it out from under itself leaves every later spex looking at
    # an empty tree, so put the path back where it was found.
    previous_nav_path = ViewStore.get_state().file_nav_path

    on_exit(fn ->
      if previous_nav_path, do: ViewStore.set_file_nav_path(previous_nav_path)
      ViewStore.sync()
      File.rm_rf(root)
    end)

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

  # Process identity is the assertion when the question is "did this survive?" —
  # a recreated SideNav looks identical from the outside until you notice every
  # folder has closed.
  defp nav_pid do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :file_nav)
    if is_list(child), do: List.first(child), else: child
  end

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

  defp choose_context_action(row) do
    %{context_menu: %{x: x, y: y}, frame: frame} = nav_state()
    left = min(x, max(frame.size.width - 150 - 4, 4))
    top = min(y, max(frame.size.height - 60 - 4, 4))
    point = {frame.pin.x + left + 30, frame.pin.y + top + row * 30 + 15}
    pointer(:btn_left, 1, [], point)
    pointer(:btn_left, 0, [], point)
    Process.sleep(200)
  end

  defp type_codepoints(text) do
    text
    |> String.graphemes()
    |> Enum.each(&ScenicMcp.Probes.send_codepoint(&1, []))
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

  # The viewport point at the vertical middle of a row.
  #
  # NOT row_center/1: semantic screen_bounds come back zero-sized for nav rows,
  # so the "centre" it computes is really the row's top-left corner — which is
  # exactly the boundary between two rows, and hit_test's bounds are inclusive
  # at both ends, so either neighbour can match. item_bounds is the map hit_test
  # itself reads, which makes it the honest source for a coordinate.
  defp row_point(path) do
    state = nav_state()
    %{y: y, height: height} = Map.fetch!(state.item_bounds, path)

    {state.frame.pin.x + 40, state.frame.pin.y + y + height / 2 - state.scroll.offset_y}
  end

  # Press and move, but do NOT release — the drag is left in flight so a
  # scenario can assert on what the navigator does while it is being held.
  defp drag_hold(source, {x, y}) do
    pointer(:btn_left, 1, [], row_point(source))
    Process.sleep(100)
    assert nav_state().drag_source == source

    {:ok, viewport} = Scenic.ViewPort.info(:main_viewport)
    # Two moves: the first crosses the drag threshold, the second is the one
    # that lands where we want with `dragging` already true.
    Scenic.ViewPort.Input.send(viewport, {:cursor_pos, {x, y}})
    Process.sleep(60)
    Scenic.ViewPort.Input.send(viewport, {:cursor_pos, {x, y}})
    Process.sleep(60)
    assert nav_state().dragging
  end

  defp drag_release({x, y}) do
    pointer(:btn_left, 0, [], {x, y})
    Process.sleep(500)
    assert nav_state().drag_source == nil
  end

  # A point in the pane below every row — the empty space that means "the
  # navigator root".
  defp empty_space_below_tree do
    state = nav_state()

    lowest =
      state.item_bounds
      |> Map.values()
      |> Enum.map(&(&1.y + &1.height))
      |> Enum.max()

    y = lowest - state.scroll.offset_y + 30
    assert y < state.frame.size.height, "the tree fills the pane; no empty space to drop into"
    {state.frame.pin.x + 40, state.frame.pin.y + y}
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

    # The navigator used to collapse to its roots twice for every file
    # operation. A status message appearing or disappearing changes the buffer
    # pane's geometry, which put the root scene on its z-order rebuild path,
    # and that path deleted :file_nav outright — killing the SideNav process
    # along with its expanded set, selection and scroll offset. Since every
    # move/rename/delete raises a toast that clears itself 8s later, the tree
    # reset once on the way in and once on the way out, seconds after the user
    # had moved on. The side pane's own frame is carved before the status strip
    # is split off, so it never needed rebuilding at all.
    scenario "A status message does not reset the tree" do
      given_ "a directory is expanded and a file selected with no status showing", context do
        opened = Path.join(context.root, "opened")
        gamma = Path.join(context.root, "gamma.txt")
        # A row click TOGGLES a directory, and earlier scenarios in this spex
        # share the tree — clicking unconditionally would collapse it here.
        unless MapSet.member?(nav_state().expanded, opened), do: click(opened)
        click(gamma, [:ctrl])

        state = nav_state()
        assert MapSet.member?(state.expanded, opened)
        assert MapSet.member?(state.selected_ids, gamma)

        {:ok, Map.merge(context, %{opened: opened, gamma: gamma, nav_pid: nav_pid()})}
      end

      when_ "an operation raises a status message", context do
        refute root_state().status_message
        ViewStore.show_status("Moved 2 entries to destination", :info)
        ViewStore.sync()
        Process.sleep(400)
        assert root_state().status_message
        {:ok, context}
      end

      then_ "the same SideNav is still alive with its expansion intact", context do
        assert nav_pid() == context.nav_pid,
               "the navigator was recreated; expansion and scroll are lost with it"

        state = nav_state()
        assert MapSet.member?(state.expanded, context.opened)
        assert MapSet.member?(state.selected_ids, context.gamma)
        {:ok, context}
      end
    end

    scenario "Clicking a binary file is rejected before it reaches the editor" do
      given_ "an executable-like file is visible", context do
        binary = Path.join(context.root, "window_pinner")
        File.write!(binary, <<0x7F, "ELF", 2, 1, 1, 0, 0, 0xFF, 0xFE>>)
        refresh_tree()

        {:ok,
         Map.merge(context, %{
           binary: binary,
           buffer_count: length(Quillex.Buffer.list())
         })}
      end

      when_ "the binary row is clicked", context do
        click(context.binary)
        ViewStore.sync()
        {:ok, context}
      end

      then_ "no buffer is created and the status bar explains the rejection", context do
        assert length(Quillex.Buffer.list()) == context.buffer_count
        assert ViewStore.get_state().status_message =~ "not UTF-8 text"
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

    # A drag can only ever drop onto what is already on screen. Both of these
    # exist so that the tree the drag started in is not the only tree it can
    # finish in: a collapsed folder opens when you rest on it, and the space
    # below the last row means the navigator root — the one destination that
    # has no row of its own to aim at.
    scenario "Resting a drag on a collapsed directory springs it open" do
      given_ "a collapsed directory and something to drag", context do
        nest = Path.join(context.root, "nest")
        gamma = Path.join(context.root, "gamma.txt")
        refresh_tree()

        if MapSet.member?(nav_state().expanded, nest), do: click(nest)
        refute MapSet.member?(nav_state().expanded, nest)

        click(gamma)
        {:ok, Map.merge(context, %{nest: nest, gamma: gamma})}
      end

      when_ "the drag hovers over it without dropping", context do
        target = row_point(context.nest)
        drag_hold(context.gamma, target)

        # The ghost only exists while a drag is in flight, so this is also the
        # only moment it can be asserted on.
        assert [_ghost] = Scenic.Graph.get(nav_scene().assigns.graph, :side_nav_drag_ghost)
        assert nav_state().drag_target == context.nest

        # Longer than the spring-load delay, which the component owns.
        Process.sleep(900)
        {:ok, Map.put(context, :target, target)}
      end

      then_ "it opens and its contents become droppable", context do
        assert MapSet.member?(nav_state().expanded, context.nest),
               "the directory did not spring open under a resting drag"

        assert Map.has_key?(nav_state().item_bounds, Path.join(context.nest, "inner"))

        drag_release(context.target)
        refute Scenic.Graph.get(nav_scene().assigns.graph, :side_nav_drag_ghost) != []
        {:ok, context}
      end
    end

    scenario "Dropping on empty space moves to the navigator root" do
      given_ "a file nested inside a subdirectory", context do
        nest = Path.join(context.root, "nest")
        inner = Path.join(nest, "inner")
        deep = Path.join(inner, "deep.txt")

        refresh_tree()
        unless MapSet.member?(nav_state().expanded, nest), do: click(nest)
        unless MapSet.member?(nav_state().expanded, inner), do: click(inner)
        assert Map.has_key?(nav_state().item_bounds, deep)

        click(deep)
        {:ok, Map.merge(context, %{deep: deep, moved: Path.join(context.root, "deep.txt")})}
      end

      when_ "it is dragged below the last row and dropped", context do
        empty = empty_space_below_tree()
        drag_hold(context.deep, empty)

        # The root has no row, so the pane border is the drop affordance.
        assert nav_state().drag_target == context.root
        assert nav_state().drop_valid
        assert [_outline] = Scenic.Graph.get(nav_scene().assigns.graph, :side_nav_root_drop_target)

        drag_release(empty)
        refresh_tree()
        {:ok, context}
      end

      then_ "the file now sits at the top level", context do
        refute File.exists?(context.deep)
        assert File.regular?(context.moved)
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
        choose_context_action(1)
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

    scenario "A directory is renamed inline from its row" do
      given_ "a directory is visible", context do
        directory = Path.join(context.root, "rename-me")
        File.mkdir_p!(directory)
        File.write!(Path.join(directory, "child.txt"), "child")
        refresh_tree()
        {:ok, Map.put(context, :rename_directory, directory)}
      end

      when_ "Rename is chosen and a new name is entered", context do
        right_click(context.rename_directory)
        choose_context_action(0)
        assert nav_state().renaming_id == context.rename_directory

        type_codepoints("renamed-directory")
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(700)
        {:ok, Map.put(context, :renamed_directory, Path.join(context.root, "renamed-directory"))}
      end

      then_ "the row and its contents move to the new path", context do
        refute File.exists?(context.rename_directory)
        assert File.read!(Path.join(context.renamed_directory, "child.txt")) == "child"
        assert String.starts_with?(ViewStore.get_state().status_message, "Renamed")
        {:ok, context}
      end
    end

    # Last, because it fills the pane with enough rows to overflow it and every
    # earlier scenario locates its rows by position.
    scenario "Holding a drag at the bottom edge scrolls the tree" do
      given_ "a tree taller than the pane", context do
        bulk = Path.join(context.root, "bulk")
        File.mkdir_p!(bulk)
        for n <- 1..80, do: File.write!(Path.join(bulk, "file_#{n}.txt"), "x")
        refresh_tree()

        unless MapSet.member?(nav_state().expanded, bulk), do: click(bulk)

        state = nav_state()

        assert state.scroll.content_height > state.frame.size.height,
               "the tree still fits the pane; there would be nothing to scroll"

        {:ok, Map.merge(context, %{bulk: bulk, offset_before: state.scroll.offset_y})}
      end

      when_ "a drag is held in the bottom edge strip", context do
        state = nav_state()
        # Inside the pane, a few pixels from its bottom edge — where the wheel
        # is unavailable because the button is still down.
        edge = {state.frame.pin.x + 40, state.frame.pin.y + state.frame.size.height - 6}

        drag_hold(Path.join(context.bulk, "file_1.txt"), edge)
        Process.sleep(600)
        {:ok, Map.put(context, :edge, edge)}
      end

      then_ "the tree scrolls under the stationary pointer", context do
        scrolled = nav_state().scroll.offset_y

        assert scrolled > context.offset_before,
               "the tree did not scroll (offset #{scrolled} vs #{context.offset_before})"

        drag_release(context.edge)

        # And it stops as soon as the drag does.
        settled = nav_state().scroll.offset_y
        Process.sleep(300)
        assert nav_state().scroll.offset_y == settled

        File.rm_rf!(context.bulk)
        refresh_tree()
        {:ok, context}
      end
    end
  end
end
