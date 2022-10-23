defmodule QuillEx.Utils.PubSub do
  @registrar_proc QuillEx.PubSub
  @topic :quillex

  # almost every component just wants to join `:quillex`
  def register do
    register(topic: @topic)
  end

  def register(topic: t) do
    {:ok, _} = Registry.register(@registrar_proc, t, [])
    :ok
  end

  def broadcast(state_change: chng) do
    Registry.dispatch(@registrar_proc, @topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:state_change, chng})
    end)
  end

  def broadcast(topic: topic, msg: msg) do
    Registry.dispatch(@registrar_proc, topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, msg)
    end)
  end
end
