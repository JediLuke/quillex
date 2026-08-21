defmodule ScenicWidgets.Menu.TreeTest do
  @moduledoc """
  The generic tree row — a menu row you can pick a SET out of.

  It lives in scenic-widget-contrib, but is tested here: contrib's own
  `mix test` cannot run at all on this machine (a NIF dependency wants gcc),
  and an untested reusable component is the thing this is meant not to be.
  Quillex is its first customer either way.
  """
  use ExUnit.Case, async: true

  alias ScenicWidgets.Menu.Model
  alias ScenicWidgets.Menu.Model.{Tree, TreeNode}

  defp leaf(id, children \\ []),
    do: %TreeNode{id: id, label: to_string(id), children: children}

  defp tree(opts \\ []) do
    %Tree{
      id: :scope,
      label: "SCOPE",
      nodes: [
        leaf(:lib, [leaf(:core, [leaf(:engine), leaf(:parser)]), leaf(:web)]),
        leaf(:readme)
      ]
    }
    |> struct!(opts)
  end

  describe "what is on screen" do
    test "a shut tree shows only its top level" do
      assert Model.visible_tree_nodes(tree()) |> Enum.map(fn {n, d} -> {n.id, d} end) ==
               [{:lib, 0}, {:readme, 0}]
    end

    test "opening a branch shows its children, one level further in" do
      opened = Model.toggle_tree_expanded(tree(), :lib)

      assert Model.visible_tree_nodes(opened) |> Enum.map(fn {n, d} -> {n.id, d} end) ==
               [{:lib, 0}, {:core, 1}, {:web, 1}, {:readme, 0}]
    end

    test "and opening one inside it goes deeper again" do
      deep =
        tree()
        |> Model.toggle_tree_expanded(:lib)
        |> Model.toggle_tree_expanded(:core)

      assert Model.visible_tree_nodes(deep) |> Enum.map(fn {n, d} -> {n.id, d} end) ==
               [{:lib, 0}, {:core, 1}, {:engine, 2}, {:parser, 2}, {:web, 1}, {:readme, 0}]
    end

    test "a shut branch hides everything under it, however deep" do
      deep =
        tree()
        |> Model.toggle_tree_expanded(:lib)
        |> Model.toggle_tree_expanded(:core)

      shut = Model.toggle_tree_expanded(deep, :lib)

      assert Model.visible_tree_nodes(shut) |> Enum.map(fn {n, _d} -> n.id end) ==
               [:lib, :readme]
    end
  end

  describe "ticking" do
    test "a node ticks and unticks, and nothing else moves with it" do
      unticked = Model.toggle_tree_node(tree(), :readme)

      refute Model.find_tree_node(unticked, :readme).checked?
      assert Model.find_tree_node(unticked, :lib).checked?
    end

    test "a node buried in the tree can be reached by id" do
      unticked =
        tree()
        |> Model.toggle_tree_expanded(:lib)
        |> Model.toggle_tree_expanded(:core)
        |> Model.toggle_tree_node(:engine)

      refute Model.find_tree_node(unticked, :engine).checked?
      assert Model.find_tree_node(unticked, :parser).checked?
    end

    test "updating a node leaves the rest of the tree alone" do
      before = tree()
      after_ = Model.toggle_tree_node(before, :core)

      assert Model.tree_node_count(after_) == Model.tree_node_count(before)
      assert Enum.map(after_.nodes, & &1.id) == Enum.map(before.nodes, & &1.id)
    end
  end

  describe "how tall it is" do
    test "counts only what is showing" do
      assert Model.tree_node_count(tree()) == 2
      assert tree() |> Model.toggle_tree_expanded(:lib) |> Model.tree_node_count() == 4
    end
  end

  test "the indent is one number, so a triangle can be clicked where it is drawn" do
    # The renderer places a branch's triangle at depth * this, and the reducer
    # decides a click hit it by the same arithmetic. Two copies would drift and
    # leave a triangle nobody can press.
    assert is_integer(Model.tree_indent())
    assert Model.tree_indent() > 0
  end
end
