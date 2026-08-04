defmodule Quillex.CommandsTest do
  use ExUnit.Case, async: true

  test "menu labels and shortcuts are generated from one registry" do
    assert Quillex.Commands.menu_label(:undo) == "Undo (Ctrl+Z)"
    assert Quillex.Commands.menu_label(:redo) == "Redo (Ctrl+Shift+Z)"
    assert Enum.any?(Quillex.Commands.shortcut_lines(), &String.contains?(&1, "Toggle Fold"))
    assert Enum.uniq_by(Quillex.Commands.all(), & &1.id) == Quillex.Commands.all()
  end
end
