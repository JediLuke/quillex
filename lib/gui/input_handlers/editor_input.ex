defmodule QuillEx.UserInputHandler.Editor do
   # - NOTE: We have this little hack `buffer_api_module` to make
   # this module re-usable by Flamelex...
   use ScenicWidgets.ScenicEventsDefinitions

   @ignorable_keys [@left_shift, @shift_space]

   def process(key, _buffer_api_module) when key in @ignorable_keys do
      IO.puts "~~~ ignorin..."
      :ignore
   end

   def process(key, buffer_api_module) when key in @valid_text_input_characters do
      buffer_api_module.active_buf()
      |> buffer_api_module.modify({:insert, key |> key2string(), :at_cursor})
   end

   def process(@backspace_key, buffer_api_module) do
      buffer_api_module.active_buf()
      |> buffer_api_module.modify({:backspace, 1, :at_cursor})
   end

   def process(key, buffer_api_module) when key in @arrow_keys do

      # REMINDER: these tuples are in the form `{line, col}`
      delta = case key do
         @left_arrow ->
            {0, -1}
         @up_arrow ->
            {-1, 0}
         @right_arrow ->
            {0, 1}
         @down_arrow ->
            {1, 0}
      end

      buffer_api_module.move_cursor(delta)
   end

   # def process meta+v is paste

   def process({:cursor_scroll, {{_x_scroll, _y_scroll} = scroll_delta, _coords}}, buffer_api_module) do
      buffer_api_module.scroll(scroll_delta)
   end

   def process(key, api_mod) do
      IO.puts "#{__MODULE__} couldn't match key!"
      dbg()
   end


end