defmodule Quillex.MenuFitsAnyWindowSpex do
  @moduledoc """
  Every menu row stays reachable, at any window size.

  The View menu has grown to five groups. Make the window short enough and it
  is taller than the room under the bar — and it drew straight past the bottom
  of the viewport and would not scroll, so the rows down there could be
  counted and never clicked.

  It was not that scrolling was missing. `IconMenu` clamps to
  `max_dropdown_height`, scrolls under the wheel, and scissors the overflow.
  The menu simply never found out the window had changed: that height is part
  of its THEME, themes were only re-pushed when the palette or the zoom
  changed, and resizing a window is neither. It went on believing it had the
  room it was built with.

  This is written as a property rather than a case: the interesting thing is
  not one window size, it is that no size leaves a row you cannot reach. It
  tries several, including sizes small enough that the menu certainly does not
  fit, and asserts the same three things of each.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.{AppReset, ViewportResizer}

  # Enough to be sure at least one is too short for the View menu.
  @heights [900, 620, 480, 380]

  defp root_state, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

  defp icon_menu_state do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, :icon_menu)
    :sys.get_state(pid, 30_000).assigns.state
  end

  defp window_height, do: root_state().frame.size.height

  defp open_menu(id) do
    Probes.click_element("icon_menu_#{id}")
    Process.sleep(250)
    :ok
  end

  defp close_menu do
    Probes.send_keys("escape", [])
    Process.sleep(200)
    :ok
  end

  defp dropdown(id), do: Map.get(icon_menu_state().dropdown_bounds, id)

  defp icon_menu_graph do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, :icon_menu)
    :sys.get_state(pid, 30_000).assigns.graph
  end

  # Where the topmost DRAWN row of the open dropdown sits, read out of the
  # graph rather than out of the state that feeds it.
  defp drawn_row_y do
    icon_menu_graph().primitives
    |> Map.values()
    |> Enum.filter(&match?({:dropdown_item, _}, &1.id))
    |> Enum.map(fn p -> p.transforms |> Map.fetch!(:translate) |> elem(1) end)
    |> Enum.min(fn -> nil end)
  end

  defp scrollbar_thumb do
    case Scenic.Graph.get(icon_menu_graph(), {:scrollbar_y_thumb, :dropdown_group}) do
      [thumb] -> thumb
      _ -> nil
    end
  end

  defp wait_until(predicate, timeout \\ 8_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait(predicate, deadline)
  end

  defp do_wait(predicate, deadline) do
    cond do
      predicate.() -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true -> Process.sleep(25) && do_wait(predicate, deadline)
    end
  end

  defp resize_to(height) do
    {w, _h} = ViewportResizer.viewport_size()
    ViewportResizer.resize(w, height)
    assert wait_until(fn -> window_height() == height end, 5_000),
           "the viewport never reached #{height} (got #{window_height()})"

    # And the menus have to have been TOLD. This is the whole bug: the layout
    # follows the window immediately, the children's themes did not.
    Process.sleep(400)
    :ok
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    {original_w, original_h} = ViewportResizer.viewport_size()

    on_exit(fn ->
      ViewportResizer.resize(original_w, original_h)
      Process.sleep(400)
    end)

    {:ok, original: {original_w, original_h}}
  end

  spex "No window size leaves a menu row you cannot reach",
    description: "Shrink the window; every dropdown still fits, scrolls, and can be read to the end",
    tags: [:phase_46, :menubar, :resize, :property] do
    scenario "every size, every menu" do
      then_ "each dropdown is inside the window, whatever size it is", context do
        for height <- @heights do
          :ok = resize_to(height)

          for menu <- [:file, :edit, :view, :help] do
            :ok = open_menu(menu)
            bounds = dropdown(menu)

            if bounds do
              assert bounds.y + bounds.height <= window_height(),
                     """
                     at a window #{height} tall, the #{menu} dropdown reaches
                     #{trunc(bounds.y + bounds.height - window_height())}px past the
                     bottom. A row below the edge cannot be clicked, so it may
                     as well not be in the menu.
                     """
            end

            :ok = close_menu()
          end
        end

        {:ok, context}
      end

      then_ "and where it does not fit, it scrolls to the end", context do
        # The shortest window, where the View menu certainly overflows.
        :ok = resize_to(List.last(@heights))
        :ok = open_menu(:view)

        bounds = dropdown(:view)

        assert bounds,
               "the view menu did not open at #{List.last(@heights)}px"

        assert bounds.content_height > bounds.height,
               """
               this window is meant to be too short for the View menu, and it
               fits (#{bounds.content_height} in #{bounds.height}). Nothing
               below proves anything.
               """

        first_row_y = bounds.items |> Map.values() |> Enum.map(& &1.y) |> Enum.min()
        context = Map.put(context, :drawn_first, drawn_row_y())

        # dropdown_bounds are in the icon menu's OWN space; the wheel is sent
        # in the viewport's.
        {pin_x, pin_y} = icon_menu_state().frame.pin.point

        Enum.each(1..10, fn _ ->
          Probes.send_scroll(
            0,
            -1,
            trunc(pin_x + bounds.x + bounds.width / 2),
            trunc(pin_y + bounds.y + 40)
          )

          Process.sleep(60)
        end)

        moved = dropdown(:view)
        now_first = moved.items |> Map.values() |> Enum.map(& &1.y) |> Enum.min()

        assert now_first < first_row_y,
               """
               the wheel did not move the View menu. It clamps and scrolls
               already — what it lacked was ever being told the window had
               shrunk, so by its own arithmetic there was nothing to scroll.
               """

        # And it moved ON SCREEN, not merely in the state. Everything above is
        # read out of `dropdown_bounds`, which is where the scroll arithmetic
        # lands — the graph is a separate step, and the renderer rebuilds the
        # dropdown only for a change it recognises. Scrolling changes nothing
        # it used to look at.
        assert drawn_row_y() < context.drawn_first,
               """
               the menu scrolled in its state and stayed where it was on the
               screen. A person turning the wheel is told nothing at all until
               something else — the next pixel of pointer movement — happens to
               rebuild the panel.
               """

        assert scrollbar_thumb(), "a clamped menu draws no scrollbar"

        :ok = close_menu()
        {:ok, context}
      end

      then_ "and the window can be put back without leaving anything clipped", context do
        {w, h} = context.original
        ViewportResizer.resize(w, h)
        assert wait_until(fn -> window_height() == h end, 5_000)
        Process.sleep(400)

        :ok = open_menu(:view)
        bounds = dropdown(:view)

        assert bounds.content_height <= bounds.height + 1,
               "back at full size the View menu should not still think it is clamped"

        :ok = close_menu()
        {:ok, context}
      end
    end
  end
end
