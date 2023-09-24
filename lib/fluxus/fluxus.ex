defmodule QuillEx.Fluxus do
  @actions_topic :quill_ex_actions
  @user_input_topic :quill_ex_user_input

  def action(a) do
    :ok =
      EventBus.notify(%EventBus.Model.Event{
        id: UUID.uuid4(),
        topic: @actions_topic,
        data: {:action, a}
      })
  end

  def user_input(i) do
    :ok =
      EventBus.notify(%EventBus.Model.Event{
        id: UUID.uuid4(),
        topic: @user_input_topic,
        data: {:user_input, i}
      })
  end
end
