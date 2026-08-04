defmodule QuillEx.AppRuntimeModeTest do
  use ExUnit.Case, async: false

  setup do
    previous = Application.get_env(:quillex, :runtime_mode)

    on_exit(fn ->
      if previous == nil,
        do: Application.delete_env(:quillex, :runtime_mode),
        else: Application.put_env(:quillex, :runtime_mode, previous)
    end)
  end

  test "runtime modes have explicit supervision shapes" do
    assert Enum.any?(QuillEx.App.children_for(:standalone), &match?({Scenic, _}, &1))
    refute Enum.any?(QuillEx.App.children_for(:embedded), &match?({Scenic, _}, &1))
    refute Enum.any?(QuillEx.App.children_for(:headless), &match?({Scenic, _}, &1))

    assert Enum.any?(
             QuillEx.App.children_for(:embedded),
             &match?({Quillex.Buffers.TopSupervisor, _}, &1)
           )
  end

  test "invalid modes fail explicitly" do
    Application.put_env(:quillex, :runtime_mode, :host_product)
    assert_raise ArgumentError, fn -> QuillEx.App.runtime_mode() end
  end
end
