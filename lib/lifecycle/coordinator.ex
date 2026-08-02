defmodule Quillex.Lifecycle.Coordinator do
  @moduledoc """
  Coordinates deferred native-window close requests with dirty-buffer policy.
  """
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def request_close(reason), do: GenServer.cast(__MODULE__, {:request_close, reason})
  def cancel, do: GenServer.cast(__MODULE__, :cancel)
  def discard_and_quit, do: GenServer.cast(__MODULE__, :discard_and_quit)

  @impl true
  def init(opts) do
    {:ok,
     %{
       driver: Keyword.get(opts, :driver, :scenic_driver),
       pending?: false,
       shutdown: Keyword.get(opts, :shutdown, {System, :stop, [0]})
     }}
  end

  @impl true
  def handle_cast({:request_close, _reason}, %{pending?: true} = state), do: {:noreply, state}

  def handle_cast({:request_close, _reason}, state) do
    case Quillex.Buffer.dirty_buffers() do
      [] ->
        complete_quit(state.driver, state.shutdown)
        {:stop, :normal, state}

      dirty ->
        if scene = Process.whereis(QuillEx.RootScene), do: send(scene, {:quit_requested, dirty})
        {:noreply, %{state | pending?: true}}
    end
  end

  def handle_cast(:cancel, state) do
    cancel_driver(state.driver)
    {:noreply, %{state | pending?: false}}
  end

  def handle_cast(:discard_and_quit, %{pending?: true} = state) do
    complete_quit(state.driver, state.shutdown)
    {:stop, :normal, %{state | pending?: false}}
  end

  def handle_cast(:discard_and_quit, state), do: {:noreply, state}

  defp authorize(driver),
    do:
      with(pid when is_pid(pid) <- resolve(driver), do: Scenic.Driver.Local.authorize_close(pid))

  defp cancel_driver(driver),
    do: with(pid when is_pid(pid) <- resolve(driver), do: Scenic.Driver.Local.cancel_close(pid))

  defp resolve(pid) when is_pid(pid), do: pid
  defp resolve(name) when is_atom(name), do: Process.whereis(name)

  @doc false
  def complete_quit(driver, {module, function, args}) do
    authorize(driver)
    apply(module, function, args)
  end
end
