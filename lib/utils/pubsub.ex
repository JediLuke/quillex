defmodule QuillEx.Utils.PubSub do


   @pubsub_registry QuillEx.PubSub
   @topic :quill_ex


   # almost every component just wants to join `:quill_ex`
   def register do
      register(topic: @topic)   
   end

   def register(topic: t) do
      {:ok, _} = Registry.register(@pubsub_registry, t, [])
      :ok
   end

   def broadcast(state_change: chng) do
      Registry.dispatch(@pubsub_registry, @topic, fn entries ->
         for {pid, _} <- entries, do: send(pid, {:state_change, chng})
      end)
   end

   def broadcast(topic: topic, msg: msg) do
      Registry.dispatch(@pubsub_registry, topic, fn entries ->
         for {pid, _} <- entries, do: send(pid, msg)
      end)
   end

end