# defmodule QuillEx.Utils.PubSub do

# @pubsub_registry QuillEx.PubSub
# @action_events "action_events"
# @gui_updates "gui_updates"

#    def register(topic: t) when t in [@action_events, @gui_updates] do
#       {:ok, _} = Registry.register(@pubsub_registry, t, [])
#       :ok
#    end

#    def broadcast(action: a) do
#       Registry.dispatch(@pubsub_registry, @action_events, fn entries ->
#          for {pid, _} <- entries, do: send(pid, {:action, a})
#       end)
#    end

#    def broadcast(gui_update: a) do
#       Registry.dispatch(@pubsub_registry, @gui_updates, fn entries ->
#          for {pid, _} <- entries, do: send(pid, {:action, a})
#       end)
#    end
# end