defmodule QuillEx.UserInputHandler do
   use ScenicWidgets.ScenicEventsDefinitions
   require Logger

   # treat key repeats as a press
   def process({:key, {key, @key_held, mods}}) do
      process({:key, {key, @key_pressed, mods}})
   end

   # ignore key-release inputs
   def process({:key, {_key, @key_released, _mods}}) do
      :ignore
   end

   # all input not handled above, can be handled as editor input
   def process(key) do
      try do
         QuillEx.UserInputHandler.Editor.process(key, QuillEx.API.Buffer)
      rescue
         FunctionClauseError ->
            Logger.warn "Input: #{inspect key} not handled by #{__MODULE__}..."
            :ignore
      end
   end

end