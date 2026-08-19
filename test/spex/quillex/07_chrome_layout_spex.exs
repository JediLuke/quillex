defmodule Quillex.ChromeLayoutSpex do
  @moduledoc """
  The chrome is where it should be — measured on screen, not asserted in state.

  ## Why this exists

  Every spex before this one asks whether things are *there*: is the tab bar
  registered, is the menu drawn, is the text visible. None of them ask *where*.
  So the whole class of "it renders, but in the wrong place" was invisible to
  the suite — a menubar drawn past the right edge of the window, the top bar
  leaving a gap after a resize, the editor starting under the tab bar. Those
  are reported by eye, days later, phrased as "the menubar is off to the
  right", and then argued about.

  ## What it measures

  The top bar is three pieces that must **tile the window exactly**: tabs from
  the left edge, the cursor position label, then the icon menu ending flush
  with the right edge. Tiling is the useful invariant because every way the
  layout can break shows up in it — a piece too wide overlaps its neighbour, a
  piece too narrow leaves a gap, a piece mispositioned runs off the edge — and
  because it holds at any window size and any zoom, so it can be checked again
  after both.

  Positions come from the semantic layer's `screen_bounds`, which is where
  things were actually drawn, in window coordinates. A component's own frame
  would only tell us what it was *told*, which is the half that is usually
  right when the picture is wrong.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias Quillex.TestHelpers.{AppReset, SemanticProbe, ViewportResizer}

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_500)
    AppReset.reset!()
    Process.sleep(400)
    :ok
  end

  defp root_state, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

  defp window, do: root_state().frame.size

  # Where an element was drawn, in window coordinates.
  defp bounds(id) do
    case SemanticProbe.dump(id) do
      %{entry: %{screen_bounds: b}} -> b
      other -> flunk("#{inspect(id)} has no drawn bounds: #{inspect(other, limit: 3)}")
    end
  end

  defp right_edge(id), do: bounds(id).left + bounds(id).width
  defp bottom_edge(id), do: bounds(id).top + bounds(id).height

  # A trap worth naming: a GROUP reports where it was placed but no size of
  # its own, while the rectangle inside it reports a real size in the group's
  # LOCAL coordinates. So the cursor label's position comes from the group and
  # its width from its backdrop, and mixing the two up silently compares a
  # screen coordinate against a local one.
  defp cursor_label_span do
    left = bounds(:cursor_pos_label).left
    {left, left + bounds(:cursor_pos_background).width}
  end

  # The icon menu is a group, so it reports no width of its own. Its four
  # buttons are what is actually on screen, and the last one's right edge is
  # the right edge of the chrome.
  @icon_buttons [:icon_menu_file, :icon_menu_edit, :icon_menu_view, :icon_menu_help]

  # How far out of true the chrome is allowed to be.
  #
  # Not a fudge factor for "close enough" — it is the size of the rounding.
  # At 130% zoom a 35px button scales to 45.5 and is drawn at 46, so the strip
  # of four lands 2px wider than the frame it was given. That is invisible and
  # not worth chasing. Being off by the amounts this spex exists to catch — a
  # bar that never moved when the window did, a piece that starts where the
  # last one ended plus its own width — is off by tens or hundreds of pixels,
  # so the two are never confused.
  @slack 2

  defp icon_menu_span do
    lefts = Enum.map(@icon_buttons, &bounds(&1).left)
    rights = Enum.map(@icon_buttons, &right_edge/1)
    {Enum.min(lefts), Enum.max(rights)}
  end

  # Asserts the whole invariant, so it can be re-checked after anything that
  # moves the furniture. Returns :ok so it reads as a statement.
  defp assert_top_bar_tiles(situation) do
    w = window().width
    {icons_left, icons_right} = icon_menu_span()
    {label_left, label_right} = cursor_label_span()

    assert_in_delta icons_right, w, @slack,
                    "#{situation}: the icon menu ends at #{icons_right} but the window is " <>
                      "#{w} wide — the menubar is #{trunc(abs(icons_right - w))}px " <>
                      "#{if icons_right > w, do: "off the right edge", else: "short of it"}"

    assert_in_delta label_right, icons_left, @slack,
                    "#{situation}: the cursor label ends at #{label_right} but " <>
                      "the icon menu starts at #{icons_left} — the top bar does not tile"

    assert label_left > 0,
           "#{situation}: the cursor label is at the far left; the tab bar has no room"

    for button <- @icon_buttons do
      b = bounds(button)

      assert b.left >= 0 and b.left + b.width <= w + @slack,
             "#{situation}: #{button} is drawn at #{b.left}..#{b.left + b.width}, " <>
               "outside a #{w}px window — it cannot be clicked"
    end

    :ok
  end

  spex "The top bar tiles the window, whatever its size",
    description: "Tabs, cursor label and icon menu meet exactly and end flush right",
    tags: [:phase_7, :chrome, :layout, :regression] do
    scenario "measuring the chrome as the window and the zoom change" do
      given_ "a freshly reset editor", context do
        AppReset.reset!()
        Process.sleep(400)

        # Remembered so the window can be put back exactly, rather than to a
        # size written down here that stops being true when the window does.
        {:ok, Map.put(context, :original_size, {window().width, window().height})}
      end

      then_ "the three pieces of the top bar meet, and the last ends at the edge", context do
        assert_top_bar_tiles("at rest")
        {:ok, context}
      end

      then_ "and the editor starts below the top bar, not under it", context do
        # The buffer pane sitting at y=0 would put the first line of every
        # document behind the tabs — visible immediately, and invisible to
        # every assertion that only asks whether text is drawn.
        top_bar_bottom = bottom_edge(:icon_menu_file)
        editor_top = bounds(:buffer_pane).top

        assert editor_top >= top_bar_bottom - 1,
               "the editor starts at y=#{editor_top}, above the top bar's bottom at " <>
                 "#{top_bar_bottom} — the first line is drawn under the tabs"

        {:ok, context}
      end

      then_ "and nothing in the chrome hangs past the bottom of the window", context do
        height = window().height

        assert bottom_edge(:background) <= height + 1,
               "the editor background runs #{trunc(bottom_edge(:background) - height)}px " <>
                 "past the bottom of the window"

        {:ok, context}
      end

      when_ "the window is resized", context do
        before = window().width
        ViewportResizer.resize(1200, 800)
        Process.sleep(900)

        assert window().width != before, "the resize did not take"
        {:ok, context}
      end

      then_ "the top bar still tiles, at the new width", context do
        # This is the one that catches a component that was drawn once and
        # never repositioned: it stays where it was while the window moves out
        # from under it, which reads exactly as "the menubar is off to the
        # right".
        assert_top_bar_tiles("after resizing to 1200x800")
        {:ok, context}
      end

      when_ "the chrome is scaled up", context do
        Quillex.RadixCache.ViewStore.set_chrome_zoom(130)
        Quillex.RadixCache.ViewStore.sync()
        Process.sleep(700)
        {:ok, context}
      end

      then_ "it still tiles — the pieces grew together, not apart", context do
        assert_top_bar_tiles("at 130% chrome zoom")
        {:ok, context}
      end

      when_ "the window is restored and the zoom put back", context do
        Quillex.RadixCache.ViewStore.set_chrome_zoom(100)
        Quillex.RadixCache.ViewStore.sync()
        {w, h} = context.original_size
        ViewportResizer.resize(w, h)
        Process.sleep(900)
        {:ok, context}
      end

      then_ "everything lines up again", context do
        {w, h} = context.original_size
        assert_top_bar_tiles("back at #{w}x#{h} and 100%")
        {:ok, context}
      end
    end
  end

  spex "A fresh editor is at its normal size",
    description: "Nothing is left zoomed or scaled from whatever ran before",
    tags: [:phase_7, :chrome, :regression] do
    scenario "checking the defaults after a reset" do
      given_ "an editor left zoomed and scaled up, as a failing spex would leave it", context do
        # Left in the state a spex abandons when it fails between scaling the
        # chrome up and setting it back. Reproduced here rather than relying on
        # some other file to leak it, because the order files run in is
        # shuffled — a guard that only works when the shuffle cooperates is not
        # a guard.
        Quillex.RadixCache.ViewStore.set_chrome_zoom(130)
        Quillex.RadixCache.ViewStore.set_text_size(30)
        Quillex.RadixCache.ViewStore.sync()
        Process.sleep(400)

        assert root_state().chrome_zoom == 130, "the setup did not take"
        {:ok, context}
      end

      when_ "the next spex resets the app", context do
        AppReset.reset!()
        Process.sleep(500)
        {:ok, context}
      end

      then_ "it finds the chrome at 100% and the text at its default size", context do
        # A spex that scales the chrome up to check a menu fits sets it back
        # afterwards — unless the assertion between the two fails. Then every
        # window for the rest of the run is drawn zoomed, which looks like a
        # rendering bug and is really the previous file's mess. This asserts
        # the reset is the thing that guarantees it, rather than each spex
        # remembering.
        state = root_state()

        assert state.chrome_zoom == 100,
               "reset left the chrome at #{state.chrome_zoom}%"

        assert state.text_size == 24,
               "reset left the text at #{state.text_size}pt"

        {:ok, context}
      end

      then_ "and the menu buttons are their normal size", context do
        # 35px at 100%. If a leaked zoom ever gets past the check above, the
        # buttons are where it would show.
        for button <- @icon_buttons do
          b = bounds(button)

          assert_in_delta b.width, 35, 2,
                          "#{button} is #{b.width}px wide, not the 35 it should be at 100% zoom"
        end

        {:ok, context}
      end
    end
  end
end
