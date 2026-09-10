defmodule Quillex.TextField.ShiftLatchTest do
  @moduledoc """
  Regression guard: a normal scroll in the buffer scrolls SIDEWAYS after
  opening a file from the global search pane.

  Shift is tracked as HELD state, because a wheel event carries no modifiers —
  the only way to know Shift is down when the wheel turns is to have watched
  the key go down and not yet come up. That makes the RELEASE load-bearing,
  and the release is exactly what gets dropped when the field stops owning the
  keyboard mid-chord.

  `Ctrl+Shift+F` is the everyday case. Key input is non-positional, so it is
  broadcast to every requester and the TextField sees the Shift press. The
  search pane then opens and the host sends `{:set_overlay_open, true}`, which
  gates ALL key input at `text_field.ex`. The user lets go of Shift; that
  release lands on the floor. Focus comes back to the buffer when a result is
  opened — and `shift_held` is still true, so every wheel event from then on
  is translated into a horizontal scroll.

  Reachable only with word wrap OFF: `State.new/1` gives an unwrapped field
  scroll direction `:both`, and the axis swap in `ScrollReducer` requires
  `:both`. With wrap on, a latched Shift is invisible — which is most of why
  this felt non-deterministic to reproduce.
  """
  use ExUnit.Case, async: true

  alias ScenicWidgets.TextField.{Reducer, State}
  alias Widgex.Frame

  @font_ttf Path.expand("../../assets/fonts/IBM_Plex_Mono/IBMPlexMono-Regular.ttf", __DIR__)

  defp field do
    State.new(%{
      frame: Frame.new(pin: {0, 0}, size: {400, 200}),
      wrap_mode: :none,
      initial_text: Enum.map_join(1..40, "\n", &"line #{&1} #{String.duplicate("x", 120)}"),
      font: %{name: :ibm_plex_mono, size: 16, path: @font_ttf}
    })
  end

  defp press_shift(state) do
    {:noop, state} = Reducer.process_input(state, {:key, {:key_leftshift, 1, []}})
    state
  end

  describe "the mechanism" do
    test "an unwrapped field scrolls in both directions" do
      assert field().scroll.direction == :both
    end

    test "with shift held, a vertical wheel scrolls horizontally" do
      state = field() |> press_shift()
      assert state.scroll.shift_held

      {:noop, scrolled} = Reducer.process_input(state, {:cursor_scroll, {0, -1, 10, 10}})

      assert scrolled.scroll.offset_x != state.scroll.offset_x,
             "shift+wheel is the horizontal scroll gesture; it must move the x offset"

      assert scrolled.scroll.offset_y == state.scroll.offset_y,
             "shift+wheel must not also scroll vertically"
    end

    test "releasing shift puts it back to vertical" do
      state = field() |> press_shift()
      {:noop, state} = Reducer.process_input(state, {:key, {:key_leftshift, 0, []}})
      refute state.scroll.shift_held
    end
  end

  describe "a release that never arrives" do
    test "focus forgets a shift that was held before the field lost the keyboard" do
      state =
        field()
        |> press_shift()
        |> State.set_overlay_open(true)
        |> State.focus()

      refute state.scroll.shift_held,
             "a shift held across a focus change can never be released, so focus must forget it"
    end

    test "blur forgets it too" do
      # Press shift in the buffer, click the sidebar, release it over there.
      state = field() |> press_shift() |> State.blur()

      refute state.scroll.shift_held,
             "the release goes to whoever has focus now, not to this field"
    end

    test "an overlay taking the keyboard forgets it" do
      state = field() |> press_shift() |> State.set_overlay_open(true)

      refute state.scroll.shift_held,
             "key input is gated from here on, so the release cannot arrive"
    end

    test "a forgotten shift means the next wheel scrolls vertically again" do
      state =
        field()
        |> press_shift()
        |> State.set_overlay_open(true)
        |> State.focus()

      {:noop, scrolled} = Reducer.process_input(state, {:cursor_scroll, {0, -1, 10, 10}})

      assert scrolled.scroll.offset_y != state.scroll.offset_y,
             "this is the reported bug: the buffer scrolled sideways instead of down"

      assert scrolled.scroll.offset_x == state.scroll.offset_x
    end
  end
end
