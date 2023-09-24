defmodule QuillEx.Fluxus do
  @actions_topic :quill_ex_actions
  @user_input_topic :quill_ex_user_input

  def action(a) do
    # :ok =
    #   EventBus.notify(%EventBus.Model.Event{
    #     id: UUID.uuid4(),
    #     topic: @actions_topic,
    #     data: {:action, a}
    #   })

    :ok = GenServer.call(QuillEx.Fluxus.RadixStore, {:action, a})
  end

  def user_input(ii) do
    # :ok =
    #   EventBus.notify(%EventBus.Model.Event{
    #     id: UUID.uuid4(),
    #     topic: @user_input_topic,
    #     data: {:user_input, i}
    #   })

    :ok = GenServer.call(QuillEx.Fluxus.RadixStore, {:user_input, ii})
  end
end
