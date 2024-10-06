defmodule MyApp.BufferSupervisor do
  use DynamicSupervisor

  # Public API

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_buffer_server(buffer_name) do
    spec = {Quillex.FluxBuffer, buffer_name}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  # Supervisor Callbacks

  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
