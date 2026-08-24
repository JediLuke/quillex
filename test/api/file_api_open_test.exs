defmodule Quillex.FileAPIOpenTest do
  @moduledoc """
  What `qlx some-file` actually promises.

  The README says `qlx notes.txt` opens a file "creating it, if it doesn't
  exist yet". The code's real contract is finer than the sentence: opening a
  missing path creates a clean, empty BUFFER bound to that path — the disk
  file appears only on the first save. Nothing asserted either half of that,
  and nothing asserted that an open→save of an untouched file round-trips the
  bytes exactly (trailing newline included). Both are the kind of behaviour a
  user notices the day it changes.
  """
  use ExUnit.Case, async: false

  alias Quillex.API.FileAPI
  alias Quillex.Buffer

  setup do
    dir = Path.join(System.tmp_dir!(), "quillex_open_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn ->
      Buffer.list()
      |> Enum.filter(&(is_binary(&1.path) and String.starts_with?(&1.path, dir)))
      |> Enum.each(&Buffer.close(&1, :discard))

      File.rm_rf!(dir)
    end)

    {:ok, dir: dir}
  end

  test "opening a path that does not exist creates a clean buffer, not a file", %{dir: dir} do
    path = Path.join(dir, "does_not_exist_yet.txt")

    assert {:ok, %{buffer_ref: ref, created: true, lines: 1, bytes: 0}} = FileAPI.open(path)

    # The buffer is bound to the path, empty, and clean — no unsaved-changes
    # prompt for a document the user has not touched.
    assert {:ok, snapshot} = Buffer.fetch(ref)
    assert snapshot.lines == [""]
    refute ref.dirty?

    # The disk file is created by the first save, not by the open.
    refute File.exists?(path)

    assert {:ok, _} = Buffer.save(ref)
    assert File.read!(path) == ""
  end

  test "an untouched file round-trips byte-for-byte through open and save", %{dir: dir} do
    path = Path.join(dir, "roundtrip.txt")
    original = "alpha\nbeta\n\ngamma with trailing space \n"
    File.write!(path, original)

    assert {:ok, %{buffer_ref: ref}} = FileAPI.open(path)

    # The trailing newline survives as a final empty line in the model...
    assert {:ok, snapshot} = Buffer.fetch(ref)
    assert List.last(snapshot.lines) == ""

    # ...and saving without editing writes back exactly what was read.
    assert {:ok, _} = Buffer.save(ref)
    assert File.read!(path) == original
  end

  test "a file with no trailing newline stays that way", %{dir: dir} do
    path = Path.join(dir, "no_trailing_newline.txt")
    original = "one\ntwo"
    File.write!(path, original)

    assert {:ok, %{buffer_ref: ref, lines: 2}} = FileAPI.open(path)
    assert {:ok, _} = Buffer.save(ref)
    assert File.read!(path) == original
  end

  test "opening an already-open path activates the existing buffer instead of duplicating it",
       %{dir: dir} do
    path = Path.join(dir, "once.txt")
    File.write!(path, "solo")

    assert {:ok, %{buffer_ref: ref1}} = FileAPI.open(path)
    assert {:ok, %{buffer_ref: ref2}} = FileAPI.open(path)

    assert ref1.uuid == ref2.uuid

    canonical = Quillex.Buffer.PathIdentity.canonical(path)
    assert Enum.count(Buffer.list(), &(&1.path == canonical)) == 1
  end
end
