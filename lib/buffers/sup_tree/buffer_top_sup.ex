defmodule Quillex.Buffers.TopSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    children = [
      {Quillex.Buffer.BufferManager, []},
      {Quillex.BufferSupervisor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
