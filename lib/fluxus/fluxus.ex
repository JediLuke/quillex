defmodule QuillEx.Fluxus do
  @actions_topic :quill_ex_actions

  def action(a) do
    :ok =
      EventBus.notify(%EventBus.Model.Event{
        id: UUID.uuid4(),
        topic: @actions_topic,
        data: {:action, a}
      })
  end
end
