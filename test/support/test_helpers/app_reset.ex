defmodule Quillex.TestHelpers.AppReset do
  @moduledoc """
  Return the running editor to a known-clean state.

  The whole spex suite shares ONE app instance, so by the later files it has
  accumulated a dozen buffers, possibly an open file navigator, a scrolled
  pane and whatever selection the previous scenario left behind. Scenarios
  written against a fresh editor then fail for reasons that have nothing to
  do with what they test — and they fail *differently* run to run, which is
  what makes such failures look random.

  Call this from a spex's `setup_all` to start from a floor rather than
  from wherever the previous file stopped.

  Buffers are closed through the buffer store rather than by clicking
  File → Close: a menu click can be lost, and a reset that silently does
  not happen is worse than no reset at all.
  """

  require Logger

  @doc """
  Close every buffer but one, empty it, and dismiss any overlay.

  Returns `:ok` once the editor is holding a single empty buffer (or after
  the attempt budget is spent — this is best-effort by design; it must never
  be the thing that fails a test).
  """
  def reset! do
    reset_layout!()
    close_extra_buffers()
    clear_active_buffer()
    :ok
  end

  @doc """
  Reset only the LAYOUT: dismiss overlays and close the file navigator.

  Safe for every spex, including those that deliberately build on buffers
  opened by earlier files — it touches no document state.

  Closing the navigator matters more than it sounds: while it is open the
  editor pane starts 250px to the right, so any test clicking at a fixed x
  hits the sidebar instead of the document. That single leak produced
  "the click did nothing" failures in unrelated spex for weeks.
  """
  def reset_layout! do
    dismiss_overlays()
    Quillex.RadixCache.ViewStore.close_file_nav()
    Quillex.RadixCache.ViewStore.close_project_search()
    Process.sleep(200)
    :ok
  end

  defp dismiss_overlays do
    # Escape closes menus, the search bar and dialogs. Twice, because the
    # first may be consumed by a dropdown and the second by the search bar.
    ScenicMcp.Probes.send_keys("escape", [])
    Process.sleep(120)
    ScenicMcp.Probes.send_keys("escape", [])
    Process.sleep(180)
  end

  defp close_extra_buffers do
    Enum.reduce_while(1..20, :ok, fn _, _ ->
      case Quillex.Buffer.list() do
        buffers when length(buffers) <= 1 ->
          {:halt, :ok}

        [_keep | rest] ->
          Enum.each(rest, &Quillex.Buffer.close(&1, :discard))

          Process.sleep(200)
          {:cont, :ok}
      end
    end)
  end

  defp clear_active_buffer do
    case Quillex.Buffer.list() do
      [buf_ref | _] ->
        # Select everything and delete it, then park the cursor at the top.
        Quillex.Buffer.dispatch(buf_ref, [
          :select_all,
          {:delete, :selection},
          {:set_cursor, {1, 1}}
        ])

        Process.sleep(150)
        :ok

      _ ->
        :ok
    end
  end
end
