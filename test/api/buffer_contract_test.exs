defmodule Quillex.BufferContractTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Quillex.Buffer
  alias Quillex.Buffer.{Ref, Snapshot}

  setup do
    path =
      Path.join(System.tmp_dir!(), "quillex_contract_#{System.unique_integer([:positive])}.txt")

    File.write!(path, "alpha\nbeta")

    on_exit(fn -> File.rm(path) end)
    {:ok, path: path}
  end

  test "public operations expose Ref and singular-cursor Snapshot", %{path: path} do
    assert {:ok, %Ref{} = ref} =
             Buffer.open(%{source: %{filepath: path}, data: ["alpha", "beta"]})

    assert {:ok, %Snapshot{ref: ^ref, cursor: {1, 1}, lines: ["alpha", "beta"]}} =
             Buffer.fetch(ref)

    assert Enum.any?(Buffer.list(), &match?(%Ref{}, &1))
    assert %Ref{uuid: uuid} = Buffer.active()
    assert uuid == ref.uuid
  end

  test "duplicate canonical paths activate one buffer", %{path: path} do
    assert {:ok, first} = Buffer.open(%{source: %{filepath: path}, data: ["alpha", "beta"]})
    alias_path = Path.join([Path.dirname(path), ".", Path.basename(path)])
    assert {:ok, second} = Buffer.open(%{source: %{filepath: alias_path}})
    assert first.uuid == second.uuid
    assert Enum.count(Buffer.list(), &(&1.uuid == first.uuid)) == 1
  end

  test "invalid actions return an error and publish no false success", %{path: path} do
    assert {:ok, ref} = Buffer.open(%{source: %{filepath: path}, data: ["alpha", "beta"]})
    assert {:ok, before} = Buffer.fetch(ref)

    capture_log(fn ->
      assert {:error, {:invalid_action, :not_a_real_action, _}} =
               Buffer.dispatch(ref, :not_a_real_action)
    end)

    assert {:ok, after_snapshot} = Buffer.fetch(ref)
    assert after_snapshot == before
  end

  test "reload performs disk I/O outside the reducer", %{path: path} do
    assert {:ok, ref} = Buffer.open(%{source: %{filepath: path}, data: ["old"]})
    File.write!(path, "new\ncontent")
    assert {:ok, %Snapshot{lines: ["new", "content"]}} = Buffer.reload(ref)
  end

  test "closing reports lifecycle errors explicitly" do
    [first | _] = Buffer.list()
    Enum.each(tl(Buffer.list()), &Buffer.close(&1, :discard))

    assert {:error, :last_buffer} = Buffer.close(first, :discard)

    missing = %{first | uuid: "missing-buffer"}
    assert {:error, :not_found} = Buffer.close(missing, :discard)
  end
end
