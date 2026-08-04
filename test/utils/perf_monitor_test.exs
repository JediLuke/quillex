defmodule Quillex.PerfMonitorTest do
  use ExUnit.Case, async: true

  test "measure executes exiting work exactly once and preserves the exit" do
    parent = self()

    assert catch_exit(
             Quillex.PerfMonitor.measure(:once, fn ->
               send(parent, :ran)
               exit(:original)
             end)
           ) == :original

    assert_receive :ran
    refute_receive :ran
  end

  test "measure preserves successful results" do
    assert Quillex.PerfMonitor.measure(:success, fn -> {:ok, 42} end) == {:ok, 42}
  end
end
