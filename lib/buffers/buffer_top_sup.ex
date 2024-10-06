# defmodule MyApp.BuffersSupervisor do
#   use DynamicSupervisor

#   def start_link(_) do
#     DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
#   end

#   def start_buffer(buffer_name) do
#     spec = {Quillex.FluxBuffer, buffer_name}
#     DynamicSupervisor.start_child(__MODULE__, spec)
#   end

#   def init(:ok) do
#     DynamicSupervisor.init(strategy: :one_for_one)
#   end
# end

defmodule MyApp.TopSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    children = [
      {Quillex.Buffer.BufferManager, []},
      {MyApp.BufferSupervisor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
