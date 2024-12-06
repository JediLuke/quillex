defmodule Quillex.Utils.PubSub do
  @registrar_proc QuillEx.PubSub
  @topic :quillex

  def subscribe, do: subscribe(topic: @topic)

  def subscribe(topic: t) do
    {:ok, _} = Registry.register(@registrar_proc, t, [])
    :ok
  end

  def broadcast(topic: topic, msg: msg) do
    Registry.dispatch(@registrar_proc, topic, fn entries ->
      # != self is supposed to prevent looped messages
      for {pid, _} <- entries, pid != self(), do: send(pid, msg)
    end)
  end
end
