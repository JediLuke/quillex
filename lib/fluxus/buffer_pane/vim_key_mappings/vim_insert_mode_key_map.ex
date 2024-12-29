defmodule Quillex.GUI.Components.BufferPane.UserInputHandler.VimKeyMappings.InsertMode do
  use ScenicWidgets.ScenicEventsDefinitions
  alias Quillex.Structs.BufState.BufRef
  require Logger

  # Treat held down keys as repeated presses
  def handle({:key, {key, @key_held, mods}}) do
    handle({:key, {key, @key_pressed, mods}})
  end

  def handle({:key, {key, @key_released, mods}}) do
    # handle(buf, {:key, {key, @key_pressed, mods}})
    :ignore
  end

  # Escape, Ctrl-C, and Ctrl-[ exit insert mode
  def handle(input) when input in [@escape_key, @ctrl_c, @ctrl_open_bracket] do
    IO.puts "HER HER HER NORMAL MODE"
    [{:set_mode, {:vim, :normal}}]
  end

  # Enter key inserts a newline
  def handle(k) when k in [@enter_key, @keypad_enter] do
    [{:newline, :at_cursor}]
  end

  # Backspace and Ctrl-H delete character before cursor
  def handle(input) when input in [@backspace_key, @ctrl_h] do
    [{:delete, :before_cursor}]
  end

  # Delete key deletes character after cursor
  def handle(@delete_key) do
    [{:delete, :at_cursor}]
  end

  # # ctrl-s saves the buffer
  # def handle(@ctrl_s) do
  #   # TODO we should be passing around BuifRefs, not stupid refs like this,
  #   # I got caught sending just the UUID instead of the map, waste of time...
  #   # {:request_save, %{uuid: buf.uuid}}
  # end

  # # Ctrl-W deletes previous word
  # def handle(@ctrl_w) do
  #   :delete_previous_word
  # end

  # # Ctrl-U deletes to beginning of line
  # def handle(@ctrl_u) do
  #   :delete_to_start_of_line
  # end

  # Tab key inserts a tab character
  def handle(@tab_key) do
    [{:insert, "\t", :at_cursor}]
  end

  # Arrow keys move cursor
  def handle(input) when input in @arrow_keys do
    case input do
      @left_arrow -> [{:move_cursor, :left, 1}]
      @up_arrow -> [{:move_cursor, :up, 1}]
      @right_arrow -> [{:move_cursor, :right, 1}]
      @down_arrow -> [{:move_cursor, :down, 1}]
    end
  end

  # Home key moves cursor to the beginning of the line
  def handle(@home_key) do
    [{:move_cursor, :line_start}]
  end

  # End key moves cursor to the end of the line
  def handle(@end_key) do
    [{:move_cursor, :line_end}]
  end

  # Valid text input characters (letters, numbers, punctuation, space, etc.)
  def handle(input) when input in @valid_text_input_characters do
    [{:insert, key2string(input), :at_cursor}]
  end

  # Unhandled inputs
  def handle(input) do
    Logger.warn("InsertMode: Unhandled input: #{inspect(input)}")
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
