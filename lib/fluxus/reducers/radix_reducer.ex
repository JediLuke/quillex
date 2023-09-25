defmodule QuillEx.Fluxus.RadixReducer do
  @moduledoc """
  This reducer works slightly different to the others... the others
  are apart of the Fluxus system. This module just contains mutation
  functions for the RadixState.
  """
  require Logger

  alias QuillEx.Fluxus.Structs.RadixState

  def process(radix_state, :open_read_only_text_pane) do
    # IO.inspect(action, label: "ACXXXION")

    new_rdx = radix_state |> RadixState.show_text_pane()

    {:ok, new_rdx}
  end

  def process(radix_state, {:minor_mode, m}) do
    # IO.inspect(action, label: "ACXXXION")

    IO.puts("CHANGING THE MINOR MODE")
    new_rdx = radix_state |> RadixState.minor_mode(m)

    {:ok, new_rdx}
  end

  def process(radix_state, :open_text_pane) do
    # IO.inspect(action, label: "ACXXXION")

    new_rdx = radix_state |> RadixState.show_text_pane_two()

    {:ok, new_rdx}
  end

  def process(radix_state, :open_text_pane_scrollable) do
    # IO.inspect(action, label: "ACXXXION")

    new_rdx = radix_state |> RadixState.show_text_pane_scrollable()

    {:ok, new_rdx}
  end

  def process(radix_state, {:scroll, input}) do
    # new_components = [
    #   ScenicWidgets.UbuntuBar.draw(),
    #   PlainText.draw(~s|Hello world!|)
    # ]

    # IO.inspect(action, label: "ACXXXION")
    # radix_state.components

    new_rdx = radix_state |> RadixState.scroll_editor({:scroll, input})
    IO.puts("SCTROLL SDCROLL - #{inspect(Enum.at(new_rdx.components, 1).scroll)}]}")

    {:ok, new_rdx}
  end

  # def change_font(%{editor: %{font: current_font}} = radix_state, new_font)
  #     when is_atom(new_font) do
  #   {:ok, {_type, new_font_metrics}} = Scenic.Assets.Static.meta(new_font)

  #   full_new_font = current_font |> Map.merge(%{name: new_font, metrics: new_font_metrics})

  #   radix_state
  #   |> put_in([:editor, :font], full_new_font)
  # end

  # def change_font_size(%{editor: %{font: current_font}} = radix_state, direction)
  #     when direction in [:increase, :decrease] do
  #   delta = if direction == :increase, do: 4, else: -4
  #   full_new_font = current_font |> Map.merge(%{size: current_font.size + delta})

  #   radix_state
  #   |> put_in([:editor, :font], full_new_font)
  # end

  # def change_editor_scroll_state(
  #       radix_state,
  #       %{inner: %{width: _w, height: _h}, frame: _f} = new_scroll_state
  #     ) do
  #   radix_state
  #   |> put_in([:editor, :scroll_state], new_scroll_state)
  # end

  def process(radix_state, :test_input_action) do
    IO.puts("PROCESSING TEST ACTION")
    {:ok, radix_state}
  end

  def process(radix_state, unknown_action) do
    IO.inspect(unknown_action, label: "ACXXXION")
    Logger.warn("Unknown action: #{inspect(unknown_action)}")
    {:ok, radix_state}
  end
end
