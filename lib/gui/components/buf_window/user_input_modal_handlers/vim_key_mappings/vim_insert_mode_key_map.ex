defmodule Quillex.GUI.Components.Buffer.UserInputHandler.VimKeyMappings.InsertMode do
  use ScenicWidgets.ScenicEventsDefinitions

  # treat held down keys as repeated presses
  def handle(buf, {:key, {key, @key_held, mods}}) do
    handle(buf, {:key, {key, @key_pressed, mods}})
  end

  # escape boots us back out to normal mode
  def handle(_buf, @escape_key) do
    {:set_mode, {:vim, :normal}}
  end

  def handle(_buf, input) when input in @arrow_keys do
    case input do
      @left_arrow -> {:move_cursor, :left, 1}
      @up_arrow -> {:move_cursor, :up, 1}
      @right_arrow -> {:move_cursor, :right, 1}
      @down_arrow -> {:move_cursor, :down, 1}
    end
  end

  def handle(_buf, input) when input in @all_letters do
    {:insert, key2string(input), :at_cursor}
  end

  def handle(_buf, input) do
    IO.puts("InsertMode: Unhandled input: #{inspect(input)}")
    :ignore
  end
end

# defmodule Flamelex.KeyMappings.Vim.InsertMode do
#   alias Flamelex.Fluxus.Structs.RadixState
#   use ScenicWidgets.ScenicEventsDefinitions

#   @ignorable_keys [@shift_space, @meta, @left_ctrl]

#   # These are convenience bindings to make the code more readable when moving cursors
#   @left_one_column {0, -1}
#   @up_one_row {-1, 0}
#   @right_one_column {0, 1}
#   @down_one_row {1, 0}

#   def process(%{editor: %{active_buf: active_buf}}, @escape_key) do
#     Flamelex.API.Buffer.modify(active_buf, {:set_mode, {:vim, :normal}})

#     # NOTE - we have to go back one column because insert & normal mode don't align on what column they're operating on...
#     Flamelex.API.Buffer.move_cursor(@left_one_column)
#   end

#   # Note, this is kind of one of those points in the project where I should
#   # really keep going, but, I have kind of solved it, so, now I need to
#   # figure out the next thing that's actually unsolved, because I
#   # need to understand the program in it's entireity before I can go for the
#   # final v1.0 release.

#   # treat key repeats as a press
#   def process(radix_state, {:key, {key, @key_held, mods}}) do
#     process(radix_state, {:key, {key, @key_pressed, mods}})
#   end

#   # ignore key-release inputs
#   def process(_radix_state, {:key, {_key, @key_released, _mods}}) do
#     :ignore
#   end

#   def process(_radix_state, key) when key in @ignorable_keys do
#     :ignore
#   end

#   def process(_radix_state, {:cursor_button, _details}) do
#     :ignore
#   end

#   # all input not handled above, can be handled as editor input
#   def process(_radix_state, key) do
#     try do
#       # TODO this is all going away when we move QuillEx over to having it's own Fluxus Tree
#       QuillEx.UserInputHandler.Editor.process(key, Flamelex.API.Buffer)
#     rescue
#       FunctionClauseError ->
#         Logger.warn("Input: #{inspect(key)} not handled by #{__MODULE__}...")
#         :ignore
#     end
#   end
# end
