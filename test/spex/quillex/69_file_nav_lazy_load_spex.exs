defmodule Quillex.FileNavLazyLoadSpex do
  @moduledoc """
  The navigator is handed one directory level at a time.

  A project is opened by reading its top level and nothing else: every
  directory in it arrives `children: :unloaded`, holding a chevron and no
  contents, and is read off disk at the moment somebody opens it. The point is
  that opening a project costs the same whether it holds thirty files or a
  hundred thousand — the old navigator walked the whole tree, to depth, before
  it could draw a single row, and on a large tree that was seconds of blocked
  scene process for a pane that shows twenty folders.

  The reading itself happens in a task, so the pane is on screen saying
  `Loading…` while the filesystem is still thinking.
  """
  use SexySpex

  alias Quillex.RadixCache.ViewStore
  alias ScenicWidgets.SideNav.Item

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(1_500)
    Quillex.TestHelpers.AppReset.reset!()

    root = Path.join(System.tmp_dir!(), "quillex_lazy_spex_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "shallow"))
    File.mkdir_p!(Path.join(root, "deep/one/two/three"))
    File.write!(Path.join(root, "top.txt"), "top")
    File.write!(Path.join(root, "shallow/leaf.txt"), "leaf")
    File.write!(Path.join(root, "deep/one/two/three/buried.txt"), "buried")

    previous_nav_path = ViewStore.get_state().file_nav_path

    on_exit(fn ->
      if previous_nav_path, do: ViewStore.set_file_nav_path(previous_nav_path)
      ViewStore.sync()
      File.rm_rf(root)
    end)

    {:ok, root: root}
  end

  defp nav_state do
    root_scene = :sys.get_state(Process.whereis(Quillex.RootScene))
    {:ok, child} = Scenic.Scene.child(root_scene, :file_nav)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid).assigns.state
  end

  defp find(tree, name), do: Enum.find(tree, &(Item.get_title(&1) == name))

  spex "The navigator loads one directory level at a time",
    description: "Opening a project reads its top level; folders are read when opened",
    tags: [:phase_69, :file_nav, :lazy] do
    scenario "Opening a project reads its top level and stops there" do
      given_ "the navigator is pointed at a nested project", context do
        ViewStore.set_file_nav_path(context.root)
        ViewStore.open_file_nav()
        ViewStore.sync()
        Process.sleep(700)
        {:ok, context}
      end

      then_ "the top level is there and the depth below it is not", context do
        tree = nav_state().tree

        assert Enum.map(tree, &Item.get_title/1) == ["deep", "shallow", "top.txt"]

        deep = find(tree, "deep")

        refute Item.loaded?(deep),
               "a directory nobody has opened was read anyway"

        assert Item.has_children?(deep),
               "an unread directory must still offer a chevron, or it can never be opened"

        {:ok, context}
      end
    end

    scenario "Opening a folder reads it, and only it" do
      when_ "a directory is expanded", context do
        send_expand(Path.join(context.root, "deep"))
        Process.sleep(500)
        {:ok, context}
      end

      then_ "its own level arrives and the level below stays unread", context do
        deep = find(nav_state().tree, "deep")

        assert Item.loaded?(deep)
        assert Enum.map(Item.get_children(deep), &Item.get_title/1) == ["one"]

        one = find(Item.get_children(deep), "one")

        refute Item.loaded?(one),
               "expanding one directory read the whole subtree under it"

        {:ok, context}
      end
    end

    scenario "The tree-sync poller watches what is open, not the whole project" do
      then_ "only loaded directories are polled", context do
        watched = :sys.get_state(Process.whereis(Quillex.Files.NavigatorTreeSync)).paths

        assert context.root in watched
        assert Path.join(context.root, "deep") in watched

        refute Path.join([context.root, "deep", "one"]) in watched,
               "the poller is re-reading directories nobody has opened"

        {:ok, context}
      end
    end
  end

  # The expand event the SideNav sends its parent when a chevron is clicked.
  # Sent directly rather than clicked, because what is under test is what the
  # scene does with it — go and read that directory — not the hit-testing that
  # produces it, which 33_file_nav_operations already drives properly.
  defp send_expand(path) do
    Scenic.Scene.send_event(Process.whereis(Quillex.RootScene), {:sidebar, :expand, path})
  end
end
