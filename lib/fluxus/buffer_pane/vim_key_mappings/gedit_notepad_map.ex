defmodule Quillex.GUI.Components.BufferPane.UserInputHandler.NotepadMap do
  @moduledoc """
  Normal text editor inputs
  """
  use ScenicWidgets.ScenicEventsDefinitions
  require Logger

  # Define missing ctrl key combinations
  @ctrl_c {:key, {:key_c, @key_pressed, ["ctrl"]}}
  @ctrl_v {:key, {:key_v, @key_pressed, ["ctrl"]}}
  @ctrl_x {:key, {:key_x, @key_pressed, ["ctrl"]}}

  # Treat held down keys as repeated presses
  def handle(buf, {:key, {key, @key_held, mods}}) do
    handle(buf, {:key, {key, @key_pressed, mods}})
  end

  # Treat released navigation keys as pressed (platform sends 0 instead of 1)
  # Handle End and Home keys since they sometimes come as release state
  def handle(buf, {:key, {:key_end, 0, []}}) do
    handle(buf, @end_key)
  end

  def handle(buf, {:key, {:key_home, 0, []}}) do
    handle(buf, @home_key)
  end

  # Ignore arrow key release events (state 0) to prevent double-processing
  def handle(_buf, {:key, {:key_left, 0, []}}) do
    [:ignore]
  end

  def handle(_buf, {:key, {:key_right, 0, []}}) do
    [:ignore]
  end

  def handle(_buf, {:key, {:key_up, 0, []}}) do
    [:ignore]
  end

  def handle(_buf, {:key, {:key_down, 0, []}}) do
    [:ignore]
  end

  # Escape key cancels text selection
  def handle(_buf, @escape_key = input) do
    Logger.warn("🚫 NotepadMap: ESCAPE - Cancel selection: #{inspect(input)}")
    [{:clear_selection}]
  end

  # Alternative Escape key pattern (release state)
  def handle(_buf, {:key, {:key_escape, 0, []}} = input) do
    Logger.warn("🚫 NotepadMap: ESCAPE (alt pattern) - Cancel selection: #{inspect(input)}")
    [{:clear_selection}]
  end

  # Enter key inserts a newline
  def handle(_buf, k) when k in [@enter_key, @keypad_enter] do
    [{:newline, :at_cursor}]
  end

  # Backspace and Ctrl-H delete character before cursor
  def handle(_buf, input) when input in [@backspace_key, @ctrl_h] do
    [{:delete, :before_cursor}]
  end

  # Delete key deletes character after cursor
  def handle(_buf, @delete_key) do
    [{:delete, :at_cursor}]
  end

  # ctrl-s saves the buffer
  def handle(buf, @ctrl_s) do
    # TODO we should be passing around BuifRefs, not stupid refs like this,
    # I got caught sending just the UUID instead of the map, waste of time...
    [{:request_save, %{uuid: buf.uuid}}]
  end

  # ctrl-a selects all (clears buffer for now)
  def handle(_buf, @ctrl_a) do
    [:empty_buffer]
  end

  # ctrl-c copies selected text to clipboard
  def handle(_buf, @ctrl_c = input) do
    Logger.warn("📋 NotepadMap: COPY command detected: #{inspect(input)}")
    [{:copy, :selection}]
  end

  # Alternative Ctrl+C pattern for different platforms
  def handle(_buf, {:key, {:key_c, 1, [:ctrl]}} = input) do
    Logger.warn("📋 NotepadMap: COPY command detected (alt pattern): #{inspect(input)}")
    [{:copy, :selection}]
  end

  # ctrl-v pastes from clipboard
  def handle(_buf, @ctrl_v = input) do
    Logger.warn("📋 NotepadMap: PASTE command detected: #{inspect(input)}")
    [{:paste, :at_cursor}]
  end

  # Alternative Ctrl+V pattern for different platforms
  def handle(_buf, {:key, {:key_v, 1, [:ctrl]}} = input) do
    Logger.warn("📋 NotepadMap: PASTE command detected (alt pattern): #{inspect(input)}")
    [{:paste, :at_cursor}]
  end

  # ctrl-x cuts selected text to clipboard
  def handle(_buf, @ctrl_x = input) do
    Logger.warn("📋 NotepadMap: CUT command detected: #{inspect(input)}")
    [{:cut, :selection}]
  end

  # Alternative Ctrl+X pattern for different platforms
  def handle(_buf, {:key, {:key_x, 1, [:ctrl]}} = input) do
    Logger.warn("📋 NotepadMap: CUT command detected (alt pattern): #{inspect(input)}")
    [{:cut, :selection}]
  end

  # Tab key inserts a tab character
  def handle(_buf, @tab_key) do
    [{:insert, "\t", :at_cursor}]
  end

  # Shift+Arrow keys for text selection (must come before regular arrow keys)
  # Support both atom and string formats for modifiers
  def handle(_buf, {:key, {:key_right, 1, [:shift]}} = input) do
    Logger.warn("✂️ NotepadMap - SELECT RIGHT (atoms): #{inspect(input)}")
    [{:select_text, :right, 1}]
  end

  def handle(_buf, {:key, {:key_right, 1, ["shift"]}} = input) do
    Logger.warn("✂️ NotepadMap - SELECT RIGHT (strings): #{inspect(input)}")
    [{:select_text, :right, 1}]
  end

  def handle(_buf, {:key, {:key_left, 1, [:shift]}} = input) do
    Logger.warn("✂️ NotepadMap - SELECT LEFT (atoms): #{inspect(input)}")
    [{:select_text, :left, 1}]
  end

  def handle(_buf, {:key, {:key_left, 1, ["shift"]}} = input) do
    Logger.warn("✂️ NotepadMap - SELECT LEFT (strings): #{inspect(input)}")
    [{:select_text, :left, 1}]
  end

  def handle(_buf, {:key, {:key_up, 1, [:shift]}} = input) do
    Logger.warn("✂️ NotepadMap - SELECT UP (atoms): #{inspect(input)}")
    [{:select_text, :up, 1}]
  end

  def handle(_buf, {:key, {:key_up, 1, ["shift"]}} = input) do
    Logger.warn("✂️ NotepadMap - SELECT UP (strings): #{inspect(input)}")
    [{:select_text, :up, 1}]
  end

  def handle(_buf, {:key, {:key_down, 1, [:shift]}} = input) do
    Logger.warn("✂️ NotepadMap - SELECT DOWN (atoms): #{inspect(input)}")
    [{:select_text, :down, 1}]
  end

  def handle(_buf, {:key, {:key_down, 1, ["shift"]}} = input) do
    Logger.warn("✂️ NotepadMap - SELECT DOWN (strings): #{inspect(input)}")
    [{:select_text, :down, 1}]
  end

  # Arrow keys move cursor (and clear selection if active)
  def handle(buf, input) when input in @arrow_keys do
    movement_action = case input do
      @left_arrow -> {:move_cursor, :left, 1}
      @up_arrow -> {:move_cursor, :up, 1}
      @right_arrow -> {:move_cursor, :right, 1}
      @down_arrow -> {:move_cursor, :down, 1}
      _ -> 
        Logger.error("❌ ARROW KEY NOT MATCHED: #{inspect(input)}")
        nil
    end
    
    if movement_action do
      # If there's an active selection, clear it before moving cursor
      if buf.selection != nil do
        Logger.warn("🔄 NotepadMap: Clearing selection before cursor movement: #{inspect(input)}")
        [:clear_selection, movement_action]
      else
        [movement_action]
      end
    else
      [:ignore]
    end
  end

  # Home key moves cursor to the beginning of the line (and clear selection if active)
  def handle(buf, @home_key) do
    if buf.selection != nil do
      Logger.warn("🔄 NotepadMap: Clearing selection before Home key movement")
      [:clear_selection, {:move_cursor, :line_start}]
    else
      [{:move_cursor, :line_start}]
    end
  end

  # End key moves cursor to the end of the line (and clear selection if active)
  def handle(buf, @end_key) do
    if buf.selection != nil do
      Logger.warn("🔄 NotepadMap: Clearing selection before End key movement")
      [:clear_selection, {:move_cursor, :line_end}]
    else
      [{:move_cursor, :line_end}]
    end
  end

  # Valid text input characters (letters, numbers, punctuation, space, etc.)
  def handle(_buf, input) when input in @valid_text_input_characters do
    text = key2string(input)
    [{:insert, text, :at_cursor}]
  end

  # Log ALL inputs to help debug
  def handle(_buf, input) do
    Logger.warn("🔍 NotepadMap: Unhandled input: #{inspect(input)}")
    
    # Add specific detection for common patterns we might be missing
    case input do
      {:key, {:key_c, _state, mods}} ->
        if :ctrl in mods or "ctrl" in mods do
          Logger.error("❌ MISSED CTRL+C: #{inspect(input)} - CHECK PATTERNS!")
        end
      {:key, {:key_v, _state, mods}} ->
        if :ctrl in mods or "ctrl" in mods do
          Logger.error("❌ MISSED CTRL+V: #{inspect(input)} - CHECK PATTERNS!")
        end
      {:key, {:key_x, _state, mods}} ->
        if :ctrl in mods or "ctrl" in mods do
          Logger.error("❌ MISSED CTRL+X: #{inspect(input)} - CHECK PATTERNS!")
        end
      _ ->
        :ok
    end
    
    [:ignore]
  end
end
