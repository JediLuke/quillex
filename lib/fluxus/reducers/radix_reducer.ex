defmodule QuillEx.Fluxus.RadixReducer do
  @moduledoc """
  This reducer works slightly different to the others... the others
  are apart of the Fluxus system. This module just contains mutation
  functions for the RadixState.
  """

  def process(radix_state, action) do
    IO.inspect(action, label: "ACXXXION")
    :ok
  end

  def change_font(%{editor: %{font: current_font}} = radix_state, new_font)
      when is_atom(new_font) do
    {:ok, {_type, new_font_metrics}} = Scenic.Assets.Static.meta(new_font)

    full_new_font = current_font |> Map.merge(%{name: new_font, metrics: new_font_metrics})

    radix_state
    |> put_in([:editor, :font], full_new_font)
  end

  def change_font_size(%{editor: %{font: current_font}} = radix_state, direction)
      when direction in [:increase, :decrease] do
    delta = if direction == :increase, do: 4, else: -4
    full_new_font = current_font |> Map.merge(%{size: current_font.size + delta})

    radix_state
    |> put_in([:editor, :font], full_new_font)
  end

  def change_editor_scroll_state(
        radix_state,
        %{inner: %{width: _w, height: _h}, frame: _f} = new_scroll_state
      ) do
    radix_state
    |> put_in([:editor, :scroll_state], new_scroll_state)
  end
end
