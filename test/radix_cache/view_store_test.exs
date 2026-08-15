defmodule Quillex.RadixCache.ViewStoreTest do
  use ExUnit.Case, async: false

  alias Quillex.RadixCache.ViewStore

  defp wait_for_view(predicate, attempts \\ 100)
  defp wait_for_view(_predicate, 0), do: flunk("view snapshot did not update")

  defp wait_for_view(predicate, attempts) do
    view = ViewStore.get_state()

    if predicate.(view) do
      view
    else
      Process.sleep(10)
      wait_for_view(predicate, attempts - 1)
    end
  end

  setup do
    if ViewStore.get_state().show_action_feedback == false,
      do: ViewStore.toggle_action_feedback()

    ViewStore.sync()

    on_exit(fn ->
      if ViewStore.get_state().show_action_feedback == false,
        do: ViewStore.toggle_action_feedback()

      ViewStore.sync()
    end)

    :ok
  end

  test "action feedback is gated without suppressing ordinary status messages" do
    ViewStore.show_status("ordinary status", :warning)
    ViewStore.toggle_action_feedback()
    ViewStore.show_action_feedback("Copied 'hidden'")
    ViewStore.sync()

    assert %{show_action_feedback: false, status_message: "ordinary status"} =
             wait_for_view(&(&1.show_action_feedback == false))

    ViewStore.toggle_action_feedback()
    ViewStore.show_action_feedback("Copied 'visible'")
    ViewStore.sync()

    assert %{show_action_feedback: true, status_message: "Copied 'visible'"} =
             wait_for_view(&(&1.status_message == "Copied 'visible'"))
  end
end
