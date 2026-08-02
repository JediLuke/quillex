defmodule Quillex.Lifecycle.CoordinatorTest do
  use ExUnit.Case, async: true

  defmodule ShutdownProbe do
    def notify(test_pid), do: send(test_pid, :shutdown)
  end

  test "an authorized standalone quit closes the driver and stops the VM" do
    driver = self()

    assert :shutdown ==
             Quillex.Lifecycle.Coordinator.complete_quit(
               driver,
               {ShutdownProbe, :notify, [self()]}
             )

    assert_receive :_authorize_close_
  end
end
