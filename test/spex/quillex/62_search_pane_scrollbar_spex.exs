defmodule Quillex.SearchPaneScrollbarSpex do
  @moduledoc """
  The search pane's scrollbar can be dragged.

  It never could. `SearchPane.State` carried `scrollbar_drag`,
  `scrollbar_drag_start` and `scrollbar_drag_offset` from its very first
  commit — copied from `SideNav` — and nothing in the component ever read or
  wrote them. The three dead fields made it look wired up. Pressing the bar
  fell through to the catch-all clause that treats every left click as a click
  on the pane, found no row under the pointer, and was dropped.

  Nothing caught it because every scroll spex in the suite tests the WHEEL,
  and the wheel worked. A bar you can see and cannot move is exactly the kind
  of thing a suite of feature-shaped tests misses.

  Everything here is read out of the pane's graph: where the thumb is drawn,
  and where the content is drawn under it.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias ScenicWidgets.SearchPane.State
  alias Quillex.TestHelpers.AppReset

  @files 30
  @matches_per_file 20

  defp pane_scene do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))

    case Scenic.Scene.child(root, :project_search_pane) do
      {:ok, [pid | _]} -> :sys.get_state(pid, 30_000)
      _ -> nil
    end
  end

  defp pane_open?, do: pane_scene() != nil
  defp pane_state, do: pane_scene().assigns.state
  defp pane_graph, do: pane_scene().assigns.graph

  # ── What is DRAWN ─────────────────────────────────────────────────────────

  defp primitive(id) do
    case Scenic.Graph.get(pane_graph(), id) do
      [p] -> p
      _ -> nil
    end
  end

  defp translate_of(id) do
    case primitive(id) do
      nil -> nil
      p -> Scenic.Primitive.get_transform(p, :translate)
    end
  end

  defp thumb_id, do: {:scrollbar_y_thumb, :search_pane}
  defp track_id, do: {:scrollbar_y_track, :search_pane}

  # Where the thumb sits down its track, as drawn.
  defp thumb_y do
    case translate_of(thumb_id()) do
      {_x, y} -> y
      nil -> nil
    end
  end

  defp thumb_height do
    case primitive(thumb_id()) do
      %{data: {_w, h, _r}} -> h
      _ -> nil
    end
  end

  # Where the results are drawn, which is the whole point of moving the bar.
  defp content_y do
    case translate_of(:search_pane_scroll) do
      {_x, y} -> y
      nil -> nil
    end
  end

  defp drawn_rows do
    pane_graph().ids
    |> Map.keys()
    |> Enum.filter(&match?({:row_bg, _}, &1))
    |> Enum.map(fn {:row_bg, id} -> id end)
    |> MapSet.new()
  end

  # The thumb's middle, in screen coordinates: the pane's pin, the body under
  # the header, the scrollbar group's own offset, then the thumb down its
  # track.
  defp thumb_centre do
    state = pane_state()
    {pin_x, pin_y} = state.frame.pin.point
    {group_x, group_y} = translate_of({:scrollbar_y_group, :search_pane})

    {trunc(pin_x + group_x + 6),
     trunc(pin_y + State.header_height(state) + group_y + thumb_y() + thumb_height() / 2)}
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

  defp write_fixture(root) do
    File.rm_rf!(root)
    File.mkdir_p!(Path.join(root, "lib"))

    Enum.each(1..@files, fn f ->
      body =
        Enum.map_join(1..(@matches_per_file * 2), "\n", fn n ->
          if rem(n, 2) == 0, do: "  def needle_#{n}(x), do: x", else: "  # line #{n}"
        end)

      File.write!(Path.join(root, "lib/module_#{f}.ex"), body)
    end)

    :ok
  end

  defp open_pane_with(root, query) do
    AppReset.reset!()
    Quillex.RadixCache.ViewStore.set_file_nav_path(root)
    Process.sleep(400)

    Probes.send_keys("f", [:ctrl, :shift])
    true = wait_until(fn -> pane_open?() end)

    Probes.click_element("search_pane_clear")
    Process.sleep(200)
    Probes.send_text(query)

    true = wait_until(fn -> drawn_rows() != MapSet.new() end, 15_000)
    true = wait_until(fn -> match?({:done, _, _, _}, pane_state().model.status) end, 15_000)
    :ok
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    root = Path.join(System.tmp_dir!(), "quillex_search_pane_scrollbar")
    write_fixture(root)

    on_exit(fn ->
      Quillex.RadixCache.ViewStore.set_file_nav_path(File.cwd!())
      Process.sleep(200)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  spex "The pane's scrollbar can be dragged",
    description: "Press the thumb, move, and the results move with it",
    tags: [:phase_41, :project_search, :search_pane, :scrollbar] do
    scenario "dragging the thumb" do
      given_ "a search with far more results than the pane can show", context do
        :ok = open_pane_with(context.root, "needle")

        scroll = pane_state().scroll

        assert scroll.content_height > scroll.viewport_height,
               """
               there is nothing to scroll, so nothing below would mean
               anything: #{scroll.content_height} of content in
               #{scroll.viewport_height} of pane.
               """

        assert thumb_y() != nil,
               "the scrollbar thumb is not drawn at all: #{inspect(pane_graph().ids |> Map.keys() |> Enum.filter(&match?({:scrollbar_y_thumb, _}, &1)))}"

        assert content_y() == 0, "the pane should start at the top"

        {:ok, context |> Map.put(:thumb_before, thumb_y()) |> Map.put(:rows_before, drawn_rows())}
      end

      when_ "the thumb is pressed and dragged down the track", context do
        {x, y} = thumb_centre()

        Probes.mouse_down(x, y)
        Process.sleep(120)

        # In steps, the way a hand does it — a single jump would not catch a
        # handler that only works from where the press happened.
        Enum.each(1..5, fn i ->
          Probes.send_mouse_move(x, y + i * 30)
          Process.sleep(60)
        end)

        {:ok, Map.put(context, :drag_to, {x, y + 150})}
      end

      then_ "the thumb moved down with the pointer", context do
        assert wait_until(fn -> thumb_y() > context.thumb_before end),
               """
               the thumb is still drawn at #{inspect(thumb_y())}, where it was
               before the drag. Pressing it did nothing at all.
               """

        {:ok, context}
      end

      then_ "and the results moved under it", context do
        assert content_y() < 0,
               "the content is still drawn at #{inspect(content_y())} — the thumb moved and the results did not"

        refute MapSet.equal?(drawn_rows(), context.rows_before),
               "the same rows are drawn after scrolling a long way down them"

        {:ok, context}
      end

      when_ "the button is released and the pointer moved again", context do
        {x, y} = context.drag_to
        Probes.mouse_up(x, y)
        Process.sleep(150)

        settled = content_y()

        Probes.send_mouse_move(x, y + 200)
        Process.sleep(200)

        {:ok, Map.put(context, :settled, settled)}
      end

      then_ "nothing moves, because the drag is over", context do
        assert content_y() == context.settled,
               """
               the pane went on scrolling after the button came up — the drag
               was never released, so the bar follows the pointer forever.
                 was #{inspect(context.settled)}, now #{inspect(content_y())}
               """

        {:ok, context}
      end
    end

    scenario "clicking the track above the thumb" do
      given_ "the pane scrolled some way down", context do
        assert content_y() < 0, "expected to still be scrolled from the drag"
        {:ok, Map.put(context, :before, content_y())}
      end

      when_ "the track is clicked above the thumb", context do
        state = pane_state()
        {pin_x, pin_y} = state.frame.pin.point
        {group_x, group_y} = translate_of({:scrollbar_y_group, :search_pane})

        assert primitive(track_id()) != nil, "the track is not drawn"

        Probes.click(
          trunc(pin_x + group_x + 6),
          trunc(pin_y + State.header_height(state) + group_y + 4)
        )

        Process.sleep(250)
        {:ok, context}
      end

      then_ "the pane pages back towards the top", context do
        assert wait_until(fn -> content_y() > context.before end),
               """
               clicking the track above the thumb should page up.
                 was #{inspect(context.before)}, now #{inspect(content_y())}
               """

        {:ok, context}
      end
    end
  end
end
