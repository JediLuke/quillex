defmodule Quillex.GUI.Components.BufferPane.State do

  defstruct [
    font: nil,
    colors: nil,
    # Where we keep track of how much we've scrolled the buffer around
    scroll_acc: {0, 0},
    # these are for vim normal mode
    operator: nil, # an operator is a key/action/function that affects next keys e.g. y10 yanks 10 lines, the operator is :y
    count: 0,
    key_history: [],
    active?: true
  ]

  #   defstruct [
  #     # affects how we render the cursor
  #     mode: nil,
  #     # the font settings for this TextPad
  #     font: nil,
  #     # hold the list of LineOfText structs
  #     lines: nil,
  #     # how much margin we want to leave around the edges
  #     margin: nil,
  #     # maintains the cursor coords, note we just support single-cursor for now
  #     cursor: %{
  #       line: nil,
  #       col: nil
  #     },
  #     opts: %{
  #       alignment: :left,
  #       wrap: :no_wrap,
  #       scroll: %{
  #         direction: :all,
  #         # An accumulator for the amount of scroll
  #         acc: {0, 0}
  #       },
  #       # toggles the display of line numbers in the left margin
  #       show_line_nums?: false
  #     }
  #   ]

  @typewriter %{
    text: :black,
    slate: :white
  }

  @cauldron %{
    text: :white,
    slate: :medium_slate_blue
  }

  def new(args) do
    %__MODULE__{
      font: default_font(),
      colors: default_colors(),
      active?: Map.get(args, :active?, true)
    }
  end

  def default_font do
    font_size = 24
    font_name = :ibm_plex_mono

    {:ok, font_metrics} = ibm_plex_mono()

    Quillex.Structs.BufState.Font.new(%{
      name: font_name,
      size: font_size,
      metrics: font_metrics
    })
  end

  def ibm_plex_mono do
    #TODO load fonts from the Scenic cache
    TruetypeMetrics.load("./assets/fonts/IBM_Plex_Mono/IBMPlexMono-Regular.ttf")
  end

  def default_colors, do: @cauldron

  # Scrolling functions

  @doc """
  Scrolls the buffer view by the given delta.
  Positive values scroll down/right, negative values scroll up/left.
  """
  def scroll(state, {delta_x, delta_y}) do
    {current_x, current_y} = state.scroll_acc
    new_scroll_acc = {current_x + delta_x, current_y + delta_y}
    %{state | scroll_acc: new_scroll_acc}
  end

  @doc """
  Scrolls the buffer view vertically by the given number of lines.
  Positive values scroll down, negative values scroll up.
  """
  def scroll_lines(state, line_count, line_height \\ 24) do
    delta_y = line_count * line_height
    scroll(state, {0, delta_y})
  end

  @doc """
  Scrolls the buffer view horizontally by the given number of characters.
  Positive values scroll right, negative values scroll left.
  """
  def scroll_chars(state, char_count, char_width \\ 12) do
    delta_x = char_count * char_width
    scroll(state, {delta_x, 0})
  end

  @doc """
  Sets the scroll position to specific coordinates.
  """
  def set_scroll(state, {x, y}) do
    %{state | scroll_acc: {x, y}}
  end

  @doc """
  Resets the scroll position to the top-left (0, 0).
  """
  def reset_scroll(state) do
    %{state | scroll_acc: {0, 0}}
  end

  @doc """
  Ensures the cursor is visible within the viewport bounds.
  Auto-scrolls if the cursor is outside the visible area.
  """
  def ensure_cursor_visible(state, cursor, viewport_width, viewport_height) do
    {scroll_x, scroll_y} = state.scroll_acc
    line_height = state.font.size
    
    # Calculate cursor pixel position
    cursor_y = (cursor.line - 1) * line_height
    
    # Check if we need to scroll vertically
    new_scroll_y = cond do
      cursor_y + scroll_y < 0 ->
        # Cursor is above viewport, scroll up
        -cursor_y
      cursor_y + scroll_y > viewport_height - line_height ->
        # Cursor is below viewport, scroll down
        -(cursor_y - viewport_height + line_height)
      true ->
        # Cursor is visible vertically
        scroll_y
    end
    
    # For now, keep horizontal scrolling as is
    # TODO: Calculate horizontal scroll based on cursor column
    new_scroll_x = scroll_x
    
    %{state | scroll_acc: {new_scroll_x, new_scroll_y}}
  end

end
