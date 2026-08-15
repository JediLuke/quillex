defmodule Quillex.GUI.ResizeSchedulerTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Quillex.GUI.ResizeScheduler

  test "a burst schedules once and retains only its newest size" do
    {state, :schedule} = ResizeScheduler.enqueue(ResizeScheduler.new(), {800, 600})
    {state, :already_scheduled} = ResizeScheduler.enqueue(state, {900, 700})
    {state, :already_scheduled} = ResizeScheduler.enqueue(state, {1000, 800})

    assert {{1000, 800}, %{pending: nil, scheduled?: false}} = ResizeScheduler.take(state)
  end

  property "every non-empty resize burst converges to its last dimensions" do
    check all(
            sizes <-
              list_of(tuple({integer(320..3840), integer(240..2160)}), min_length: 1)
          ) do
      {actions, state} =
        Enum.map_reduce(sizes, ResizeScheduler.new(), fn size, state ->
          {state, action} = ResizeScheduler.enqueue(state, size)
          {action, state}
        end)

      assert Enum.count(actions, &(&1 == :schedule)) == 1
      expected_size = List.last(sizes)
      assert {^expected_size, reset} = ResizeScheduler.take(state)
      assert reset == ResizeScheduler.new()
    end
  end
end
