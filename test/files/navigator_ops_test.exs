defmodule Quillex.Files.NavigatorOpsTest do
  use ExUnit.Case, async: true

  alias Quillex.Files.NavigatorOps

  @tag :tmp_dir
  test "moves multiple files after validating the complete request", %{tmp_dir: root} do
    source_dir = Path.join(root, "source")
    target_dir = Path.join(root, "target")
    File.mkdir_p!(source_dir)
    File.mkdir_p!(target_dir)
    one = Path.join(source_dir, "one.txt")
    two = Path.join(source_dir, "two.txt")
    File.write!(one, "one")
    File.write!(two, "two")

    assert {:ok, moves} = NavigatorOps.move([one, two], target_dir)
    assert length(moves) == 2
    assert File.read!(Path.join(target_dir, "one.txt")) == "one"
    assert File.read!(Path.join(target_dir, "two.txt")) == "two"
    refute File.exists?(one)
    refute File.exists?(two)
  end

  @tag :tmp_dir
  test "rejects collisions and directory descendant moves without changing disk", %{tmp_dir: root} do
    source = Path.join(root, "source")
    child = Path.join(source, "child")
    target = Path.join(root, "target")
    File.mkdir_p!(child)
    File.mkdir_p!(target)
    File.write!(Path.join(source, "same.txt"), "source")
    File.write!(Path.join(target, "same.txt"), "target")

    assert {:error, {:destination_exists, _}} =
             NavigatorOps.move([Path.join(source, "same.txt")], target)

    assert File.read!(Path.join(source, "same.txt")) == "source"
    assert File.read!(Path.join(target, "same.txt")) == "target"
    assert {:error, {:move_into_descendant, _, _}} = NavigatorOps.move([source], child)
    assert File.dir?(source)
  end

  @tag :tmp_dir
  test "deletes confirmed files and directories recursively", %{tmp_dir: root} do
    file = Path.join(root, "file.txt")
    directory = Path.join(root, "directory")
    File.write!(file, "text")
    File.mkdir_p!(directory)
    File.write!(Path.join(directory, "nested.txt"), "nested")

    assert {:ok, deleted} = NavigatorOps.delete([file, directory])
    assert MapSet.new(deleted) == MapSet.new([file, directory])
    refute File.exists?(file)
    refute File.exists?(directory)
  end
end
