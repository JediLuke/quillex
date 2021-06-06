defmodule QuillEx.Utils do
  alias Scenic.ViewPort
    
  def vp_width(vp) do
    {:ok, %ViewPort.Status{size: {w, _h}} = viewport} = ViewPort.info(vp)
    # make a small adjustment, make it 1 pixel wider
    # Scenic doesn't paint all the way to the right for some reason...
    w+1
  end

  def vp_height(vp) do
    {:ok, %ViewPort.Status{size: {_w, h}} = viewport} = ViewPort.info(vp)
    h
  end

  defmodule PubSub do
    @pubsub_registry QuillEx.PubSub
    @action_events "action_events"
    @gui_updates "gui_updates"

    def register(topic: t) when t in [@action_events, @gui_updates] do
      {:ok, _} = Registry.register(@pubsub_registry, t, [])
      :ok
    end
  
    def broadcast(action: a) do
      Registry.dispatch(@pubsub_registry, @action_events, fn entries ->
        for {pid, _} <- entries, do: send(pid, {:action, a})
      end)
    end

    def broadcast(gui_update: a) do
      Registry.dispatch(@pubsub_registry, @gui_updates, fn entries ->
        for {pid, _} <- entries, do: send(pid, {:action, a})
      end)
    end
  end
end