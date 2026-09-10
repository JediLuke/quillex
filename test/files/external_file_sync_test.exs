defmodule Quillex.Files.ExternalFileSyncTest do
  use ExUnit.Case, async: false

  alias Quillex.Buffer
  alias Quillex.Files.ExternalFileSync
  alias Quillex.RadixCache.ViewStore

  setup do
    path = temp_path("watched")
    File.write!(path, "original")
    {:ok, ref} = Buffer.open(%{source: %{filepath: path}, data: ["original"]})

    # Establish the disk baseline before the test performs its external write.
    :ok = ExternalFileSync.sync()

    on_exit(fn ->
      Buffer.close(ref, :discard)
      File.rm(path)
    end)

    {:ok, path: path, ref: ref}
  end

  test "a clean active buffer reloads and reports the external change", %{path: path, ref: ref} do
    File.write!(path, "changed\non disk")

    :ok = ExternalFileSync.poll_now()
    ViewStore.sync()

    assert {:ok, snapshot} = Buffer.fetch(ref)
    assert snapshot.lines == ["changed", "on disk"]
    refute snapshot.ref.dirty?
    assert snapshot.ref.external_change == nil
    assert status_message() == "Reloaded #{Path.basename(path)} from disk"
  end

  test "a clean inactive buffer reloads without activating it", %{path: path, ref: ref} do
    other_path = temp_path("active")
    File.write!(other_path, "active")
    {:ok, active_ref} = Buffer.open(%{source: %{filepath: other_path}, data: ["active"]})
    :ok = ExternalFileSync.sync()

    on_exit(fn ->
      Buffer.close(active_ref, :discard)
      File.rm(other_path)
    end)

    assert Buffer.active().uuid == active_ref.uuid
    File.write!(path, "inactive tab updated")

    :ok = ExternalFileSync.poll_now()

    assert {:ok, snapshot} = Buffer.fetch(ref)
    assert snapshot.lines == ["inactive tab updated"]
    assert Buffer.active().uuid == active_ref.uuid
  end

  test "an external write never overwrites a dirty buffer", %{path: path, ref: ref} do
    assert {:ok, dirty} = Buffer.dispatch(ref, {:insert, "local ", :at_cursor})
    assert dirty.ref.dirty?
    File.write!(path, "external replacement")

    :ok = ExternalFileSync.poll_now()
    ViewStore.sync()

    assert {:ok, snapshot} = Buffer.fetch(ref)
    assert snapshot.lines == ["local original"]
    assert snapshot.ref.dirty?
    assert snapshot.ref.external_change == :modified
    assert status_message() =~ "unsaved edits preserved"
  end

  test "deleting a backing file preserves the buffer and marks it", %{path: path, ref: ref} do
    File.rm!(path)

    :ok = ExternalFileSync.poll_now()
    ViewStore.sync()

    assert {:ok, snapshot} = Buffer.fetch(ref)
    assert snapshot.lines == ["original"]
    assert snapshot.ref.external_change == :deleted
    assert status_message() =~ "was deleted on disk; buffer preserved"
  end

  # The buffer is clean — the user never touched it — and it is nonetheless the
  # only place that content still exists. It must not be closeable by accident.
  test "a deleted backing file makes an untouched buffer unsaved", %{path: path, ref: ref} do
    File.rm!(path)

    :ok = ExternalFileSync.poll_now()

    assert {:ok, snapshot} = Buffer.fetch(ref)
    refute snapshot.ref.dirty?
    assert snapshot.ref.external_change == :deleted

    # The buffer list carries the mark through to everything that reads it.
    Quillex.Buffer.BufferManager.sync()
    listed = Enum.find(Buffer.list(), &(&1.uuid == ref.uuid))
    assert listed.external_change == :deleted

    assert Buffer.unsaved?(listed)
    assert Enum.any?(Buffer.unsaved_buffers(), &(&1.uuid == ref.uuid))

    # Quit asks about exactly this list, so a deleted-file buffer now stops it.
    assert {:error, :deleted_on_disk} = Buffer.close(listed)
  end

  # Quitting used to consult only the dirty buffers, so a clean buffer whose
  # file had been deleted let the whole app exit without a word. `pending?:
  # true` is the Coordinator saying it stopped to ask; the alternative branch
  # calls complete_quit/2 and returns {:stop, :normal, _}.
  test "quitting stops to ask about a deleted-file buffer", %{path: path, ref: ref} do
    File.rm!(path)
    :ok = ExternalFileSync.poll_now()
    assert {:ok, _snapshot} = Buffer.fetch(ref)
    Quillex.Buffer.BufferManager.sync()

    assert Enum.any?(Buffer.unsaved_buffers(), &(&1.uuid == ref.uuid))

    state = %{driver: self(), pending?: false, shutdown: {Function, :identity, [:never_called]}}

    assert {:noreply, %{pending?: true}} =
             Quillex.Lifecycle.Coordinator.handle_cast({:request_close, :window_close}, state)
  end

  test "save_as retargets synchronization to the new canonical path", %{path: old_path, ref: ref} do
    new_path = temp_path("retargeted")
    on_exit(fn -> File.rm(new_path) end)

    assert {:ok, saved} = Buffer.save_as(ref, new_path)
    assert saved.ref.path == Path.expand(new_path)
    Quillex.Buffer.BufferManager.sync()
    :ok = ExternalFileSync.sync()

    File.write!(old_path, "old path should no longer matter")
    File.write!(new_path, "new path changed")
    :ok = ExternalFileSync.poll_now()

    assert {:ok, snapshot} = Buffer.fetch(ref)
    assert snapshot.lines == ["new path changed"]
    assert snapshot.ref.path == Path.expand(new_path)
  end

  test "Quillex's own save is absorbed without creating a conflict", %{path: path, ref: ref} do
    assert {:ok, _dirty} = Buffer.dispatch(ref, {:insert, "saved ", :at_cursor})
    assert {:ok, _saved} = Buffer.save(ref)
    :ok = ExternalFileSync.poll_now()

    assert File.read!(path) == "saved original"
    assert {:ok, snapshot} = Buffer.fetch(ref)
    assert snapshot.lines == ["saved original"]
    refute snapshot.ref.dirty?
    assert snapshot.ref.external_change == nil
  end

  defp status_message do
    case ViewStore.get_state() do
      {:data, %{status_message: message}, _meta} -> message
      %{status_message: message} -> message
    end
  end

  defp temp_path(label) do
    Path.join(
      System.tmp_dir!(),
      "quillex_external_sync_#{label}_#{System.unique_integer([:positive])}.txt"
    )
  end
end
