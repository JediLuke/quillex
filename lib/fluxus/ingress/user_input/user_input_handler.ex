defmodule QuillEx.Fluxus.UserInputHandler do
  use ScenicWidgets.ScenicEventsDefinitions

  def handle(radix_state, input) do
    # {:action, :test_input_action}

    # {:scroll, {{:cursor_scroll, {{0.0, -1.0}, {459.0, 434.0}}}, QuillEx.GUI.Components.PlainTextScrollable}}

    :ignored
  end

  def handle(radix_state, input) do
    # {:action, :test_input_action}
    :ignored
  end
end

# defmodule QuillEx.UserInputHandler do
#   use ScenicWidgets.ScenicEventsDefinitions
#   require Logger

#   # treat key repeats as a press
#   def process({:key, {key, @key_held, mods}}) do
#     process({:key, {key, @key_pressed, mods}})
#   end

#   # ignore key-release inputs
#   def process({:key, {_key, @key_released, _mods}}) do
#     :ignore
#   end

#   def process({:key, {k, @key_released, _mods}}) when k in [@left_shift, @right_shift] do
#     :ignore
#   end

#   # all input not handled above, can be handled as editor input
#   def process(key) do
#     try do
#       QuillEx.UserInputHandler.Editor.process(key)
#     rescue
#       FunctionClauseError ->
#         Logger.warn("Input: #{inspect(key)} not handled by #{__MODULE__}...")
#         :ignore
#     end
#   end
# end
