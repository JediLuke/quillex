defmodule Quillex.GUI.Components.BufferPane.UserInputHandler.NotepadMap do
  @moduledoc """
  Normal text editor inputs
  """
  use ScenicWidgets.ScenicEventsDefinitions

  # Treat held down keys as repeated presses
  def handle(buf, {:key, {key, @key_held, mods}}) do
    handle(buf, {:key, {key, @key_pressed, mods}})
  end

  # Enter key inserts a newline
  def handle(_buf, k) when k in [@enter_key, @keypad_enter] do
    {:newline, :at_cursor}
  end

  # Backspace and Ctrl-H delete character before cursor
  def handle(_buf, input) when input in [@backspace_key, @ctrl_h] do
    {:delete, :before_cursor}
  end

  # Delete key deletes character after cursor
  def handle(_buf, @delete_key) do
    {:delete, :at_cursor}
  end

  # ctrl-s saves the buffer
  def handle(buf, @ctrl_s) do
    # TODO we should be passing around BuifRefs, not stupid refs like this,
    # I got caught sending just the UUID instead of the map, waste of time...
    {:request_save, %{uuid: buf.uuid}}
  end

  # ctrl-a selects all (clears buffer for now)
  def handle(_buf, @ctrl_a) do
    :empty_buffer
  end

  # Tab key inserts a tab character
  def handle(_buf, @tab_key) do
    {:insert, "\t", :at_cursor}
  end

  # Arrow keys move cursor
  def handle(_buf, input) when input in @arrow_keys do
    case input do
      @left_arrow -> {:move_cursor, :left, 1}
      @up_arrow -> {:move_cursor, :up, 1}
      @right_arrow -> {:move_cursor, :right, 1}
      @down_arrow -> {:move_cursor, :down, 1}
    end
  end

  # Home key moves cursor to the beginning of the line
  def handle(_buf, @home_key) do
    {:move_cursor, :line_start}
  end

  # End key moves cursor to the end of the line
  def handle(_buf, @end_key) do
    {:move_cursor, :line_end}
  end

  # Valid text input characters (letters, numbers, punctuation, space, etc.)
  def handle(_buf, input) when input in @valid_text_input_characters do
    {:insert, key2string(input), :at_cursor}
  end

  # Unhandled inputs
  def handle(_buf, input) do
    Logger.warn("InsertMode: Unhandled input: #{inspect(input)}")
    :ignore
  end
end
