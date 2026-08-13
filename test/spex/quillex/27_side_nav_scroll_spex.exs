defmodule Quillex.SideNavScrollSpex do
  @moduledoc """
  Phase 27: the file navigator scrolls, and the status label tracks the cursor.

  These cover three regressions that a full green suite completely missed,
  which is the point of the file. Every existing spex drove the *buffer* — so
  scroll was only ever exercised through TextField, and the sidebar's own
  scroll path had no coverage at all:

  1. **The sidebar never scrolled, either axis.** Scroll is positional input,
     and Scenic hit-tests it only against primitives that named `:cursor_scroll`
     in their own `input:` list. No SideNav primitive did, so a wheel event over
     the sidebar found no target there. It was supposed to arrive by the root
     scene forwarding it via `put_child`, which never worked. SideNav now
     requests `:cursor_scroll` itself and bounds-checks the pointer, the same
     shape TextField uses.

  2. **Horizontal was doubly broken** — even once events arrived, the reducer
     pattern-matched `dx` and threw it away, so only `dy` could ever move.

  3. **"Ln X, Col Y" is chrome, so `get_rendered_text_string/0` filters it out.**
     Assertions here read `extract_rendered_text/0` instead. A test written the
     obvious way would pass against a label frozen at "Ln 1, Col 1".

  Scroll assertions compare *semantic screen bounds* of the same row before and
  after, rather than pixels or hardcoded coordinates: the window manager may
  grant a smaller window than requested and the layout reflows to match.
  """
  use SexySpex

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.{SemanticHelpers, SemanticProbe, ScriptInspector}
  alias Quillex.Utils.SideNavThemes

  # Comfortably inside the 250px-wide navigator, and below the top bar.
  @nav_x 100
  @nav_y 400
  @top_bar_h 40

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(2000)
    Quillex.TestHelpers.AppReset.reset!()
    :ok
  end

  # The first few nav rows, as {id, top, left}, in registration order.
  defp nav_rows(limit \\ 3) do
    all_rows()
    |> Enum.take(limit)
    |> Enum.map(fn {id, _top} ->
      %{entry: %{screen_bounds: %{top: top, left: left}}} = SemanticProbe.dump(id)
      {id, top, left}
    end)
  end

  # A sidebar taller than its contents has nothing to scroll, and `handle_scroll`
  # correctly clamps to a no-op — indistinguishable, from outside, from the bug
  # this file exists to catch. At the spex window size this repo's ~36 top-level
  # entries fit with room to spare, so the tree has to be made taller than the
  # viewport before scrolling means anything.
  #
  # Done by expanding directories rather than by shrinking the window: resizing
  # mid-suite left the layout in a state later spex could not recover from
  # (the buffer pane's semantic frame went missing), and it is the tree's
  # height we actually care about here.
  defp open_nav do
    Quillex.RadixCache.ViewStore.open_file_nav()
    Process.sleep(1000)
  end

  # Only the scroll scenarios need a tree taller than the sidebar; measuring
  # font pitch does not, and making that scenario pay for the expansion made it
  # fail for a reason that had nothing to do with what it asserts.
  defp open_nav_overflowing do
    open_nav()
    expand_until_overflowing()
  end

  # Expand the fattest directory still collapsed, until the tree is taller than
  # the sidebar. Measured from what is actually on screen (the span of row tops)
  # rather than from a row count, because only rows whose parents are expanded
  # contribute height — counting registered ids overstates it.
  defp expand_until_overflowing(attempts \\ 14) do
    {_, viewport_h} = Quillex.TestHelpers.ViewportResizer.viewport_size()
    # The sidebar runs from below the top bar to the bottom of the window, so
    # it is shorter than the window itself. Clearing the full window height is
    # a deliberately conservative way to guarantee the content overflows it.
    rows = all_rows()
    span = rendered_span(rows)

    if span > viewport_h do
      :ok
    else
      candidates =
        rows
        # Only rows actually on screen can be clicked — a directory is no use
        # if earlier expansions have pushed it past the bottom edge.
        |> Enum.filter(fn {_id, top} -> top > @top_bar_h and top < viewport_h - 40 end)
        |> Enum.filter(fn {id, _top} ->
          directory?(id) and not expanded?(id, rows) and not clicked?(id)
        end)
        # Document order. Walking top-to-bottom keeps the coordinates we just
        # measured valid; expansions only ever push rows further down.
        |> Enum.sort_by(fn {_id, top} -> top end)

      case {candidates, attempts} do
        {[], _} ->
          flunk("ran out of directories to expand; span #{span} <= #{viewport_h}")

        {_, 0} ->
          flunk(
            "could not grow the tree taller than the sidebar " <>
              "(span #{span} <= #{viewport_h}); scroll assertions would be vacuous"
          )

        {[{id, top} | _], _} ->
          # Click the chevron hit area, not the row: a row click navigates.
          # It sits at padding_left (10) minus 2 and is ~22px wide, so x=18 is
          # comfortably inside it. Rows are item_height (17 + 10) tall.
          Probes.click(18, trunc(top) + 13)
          mark_clicked(id)
          Process.sleep(700)
          expand_until_overflowing(attempts - 1)
      end
    end
  end

  defp rendered_span(rows) do
    case rows do
      [] -> 0
      rows -> rows |> Enum.map(&elem(&1, 1)) |> Enum.min_max() |> then(fn {lo, hi} -> hi - lo end)
    end
  end

  defp child_count(id) do
    case id |> path_of() |> File.ls() do
      {:ok, entries} -> length(entries)
      _ -> 0
    end
  end

  # Row GROUPS are registered as atoms (:"row_<abs path>"). The clickable rects
  # inside them are registered as {:row_click, path} tuples and match the same
  # regex — counting those doubled the apparent row count and broke atom-only
  # helpers, so keep just the atoms.
  defp all_rows do
    SemanticProbe.ids(~r/row_/)
    |> Map.fetch!(:index)
    |> Enum.filter(&(is_atom(&1) and String.starts_with?(Atom.to_string(&1), "row_")))
    |> Enum.map(fn id ->
      %{entry: %{screen_bounds: %{top: top}}} = SemanticProbe.dump(id)
      {id, top}
    end)
  end

  defp path_of(id), do: id |> Atom.to_string() |> String.replace_prefix("row_", "")
  defp directory?(id), do: id |> path_of() |> File.dir?()

  # Read expansion off the tree itself — a directory is expanded when its
  # children are registered — rather than remembering what we clicked. Scenarios
  # share one app, so a previous one may have expanded things already, and
  # re-clicking a chevron collapses it again.
  defp expanded?(id, rows) do
    parent = path_of(id)
    Enum.any?(rows, fn {other, _} -> Path.dirname(path_of(other)) == parent end)
  end

  # Belt and braces alongside expanded?/2: a chevron click toggles, so clicking
  # the same directory twice collapses what we just opened and the loop spins.
  defp clicked?(id), do: id in Process.get(:clicked_dirs, [])
  defp mark_clicked(id), do: Process.put(:clicked_dirs, [id | Process.get(:clicked_dirs, [])])

  defp side_nav_state do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :file_nav)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid).assigns.state
  end

  spex "The file navigator scrolls under the wheel",
    description: "Vertical and horizontal wheel events over the sidebar move its contents",
    tags: [:phase_27, :side_nav, :scroll] do
    scenario "Overflowing directories reveal their scrollbars immediately" do
      when_ "directories are expanded until the navigator overflows", context do
        open_nav_overflowing()
        {:ok, context}
      end

      then_ "the scrollbar is already visible without a wheel event", context do
        state = side_nav_state()

        assert state.scroll.content_height > state.scroll.viewport_height
        assert state.scroll.scrollbar_visible
        assert state.scroll.scrollbar_opacity == 255

        root = :sys.get_state(Process.whereis(QuillEx.RootScene))
        {:ok, child} = Scenic.Scene.child(root, :file_nav)
        nav_pid = if is_list(child), do: List.first(child), else: child
        graph = :sys.get_state(nav_pid).assigns.graph
        [thumb] = Scenic.Graph.get(graph, {:scrollbar_y_thumb, :default})
        [scrollbar_group] = Scenic.Graph.get(graph, {:scrollbar_y_group, :default})
        [content_scissor] = Scenic.Graph.get(graph, :sidebar_scroll_group_scissor)

        assert Scenic.Primitive.get_style(thumb, :fill) ==
                 {:color, {:color_rgba, {185, 190, 205, 255}}}

        # Keep the bar away from the navigator's outer edge, where the pane
        # border and resize grip otherwise make it look absent.
        assert Scenic.Primitive.get_transform(scrollbar_group, :translate) == {236, 2}

        assert Scenic.Primitive.get_style(content_scissor, :scissor) ==
                 state.frame.size.box

        {:ok, context}
      end
    end

    scenario "Wheel over the sidebar scrolls it vertically" do
      given_ "the file navigator is open and showing rows", context do
        open_nav_overflowing()
        rows = nav_rows()

        assert length(rows) >= 3,
               "expected the navigator to register rows, got: #{inspect(rows)}"

        {:ok, Map.put(context, :before, rows)}
      end

      when_ "we scroll down with the pointer over the sidebar", context do
        Probes.send_scroll(0, -5, @nav_x, @nav_y)
        Process.sleep(600)
        {:ok, context}
      end

      then_ "those rows have moved up", context do
        after_rows = nav_rows()

        moved =
          Enum.zip(context.before, after_rows)
          |> Enum.filter(fn {{id_a, top_a, _}, {id_b, top_b, _}} ->
            id_a == id_b and top_b < top_a
          end)

        all = all_rows()
        tops = Enum.map(all, fn {_, top} -> top end)

        assert length(moved) >= 1,
               """
               Scrolling down over the sidebar did not move any row upward.
               rows: #{length(all)}  top span: #{inspect(Enum.min(tops))}..#{inspect(Enum.max(tops))}
               before: #{inspect(context.before)}
               after:  #{inspect(after_rows)}
               """

        {:ok, context}
      end
    end

    scenario "Wheel sideways over the sidebar scrolls it horizontally" do
      given_ "the file navigator is open, scrolled back to the left", context do
        open_nav_overflowing()
        # Undo any horizontal offset a previous scenario left behind.
        Probes.send_scroll(20, 0, @nav_x, @nav_y)
        Process.sleep(500)

        {:ok, Map.put(context, :before, nav_rows())}
      end

      when_ "we scroll right with the pointer over the sidebar", context do
        Probes.send_scroll(-5, 0, @nav_x, @nav_y)
        Process.sleep(600)
        {:ok, context}
      end

      then_ "those rows have moved left", context do
        after_rows = nav_rows()

        moved =
          Enum.zip(context.before, after_rows)
          |> Enum.filter(fn {{id_a, _, left_a}, {id_b, _, left_b}} ->
            id_a == id_b and left_b < left_a
          end)

        assert length(moved) >= 1,
               """
               Scrolling sideways over the sidebar did not move any row left.
               before: #{inspect(context.before)}
               after:  #{inspect(after_rows)}
               """

        {:ok, context}
      end
    end

    scenario "Dragging the vertical scrollbar thumb scrolls the navigator" do
      given_ "an overflowing navigator reset to its top edge", context do
        open_nav_overflowing()
        Probes.send_scroll(0, 10_000, @nav_x, @nav_y)
        Process.sleep(500)

        {:ok, Map.put(context, :before, nav_rows())}
      end

      when_ "we grab its vertical thumb and drag it downward", context do
        {_, viewport_h} = Quillex.TestHelpers.ViewportResizer.viewport_size()

        %{entry: %{screen_bounds: %{left: left, top: top, width: width}}} =
          SemanticProbe.dump({:scrollbar_y_thumb, :default})

        x = left + width / 2
        grab_y = @top_bar_h + top + 10
        drop_y = trunc(viewport_h * 0.55)

        Probes.mouse_down(x, grab_y)
        Process.sleep(100)
        Probes.send_mouse_move(x, drop_y)
        Process.sleep(100)
        Probes.mouse_up(x, drop_y)
        Process.sleep(600)

        {:ok, context}
      end

      then_ "the visible rows move upward", context do
        after_rows = nav_rows()

        moved? =
          Enum.zip(context.before, after_rows)
          |> Enum.any?(fn {{id_a, top_a, _}, {id_b, top_b, _}} ->
            id_a == id_b and top_b < top_a
          end)

        assert moved?,
               "dragging the navigator's vertical scrollbar thumb did not move its rows"

        {:ok, context}
      end
    end

    scenario "Clicking empty vertical scrollbar track pages the navigator" do
      given_ "an overflowing navigator reset to its top edge", context do
        open_nav_overflowing()
        Probes.send_scroll(0, 10_000, @nav_x, @nav_y)
        Process.sleep(500)

        {:ok, Map.put(context, :before, nav_rows())}
      end

      when_ "we click the track well below its thumb", context do
        {_, viewport_h} = Quillex.TestHelpers.ViewportResizer.viewport_size()

        %{entry: %{screen_bounds: %{left: left, width: width}}} =
          SemanticProbe.dump({:scrollbar_y_track, :default})

        Probes.click(left + width / 2, trunc(viewport_h * 0.75))
        Process.sleep(600)
        {:ok, context}
      end

      then_ "the visible rows page upward", context do
        after_rows = nav_rows()

        moved? =
          Enum.zip(context.before, after_rows)
          |> Enum.any?(fn {{id_a, top_a, _}, {id_b, top_b, _}} ->
            id_a == id_b and top_b < top_a
          end)

        assert moved?, "clicking below the navigator thumb did not page its rows"
        {:ok, context}
      end
    end

    scenario "Clicking empty horizontal scrollbar track pages the navigator" do
      given_ "a horizontally overflowing navigator reset to its left edge", context do
        open_nav_overflowing()
        Probes.send_scroll(10_000, 0, @nav_x, @nav_y)
        Process.sleep(500)

        state = side_nav_state()
        assert state.scroll.content_width > state.scroll.viewport_width
        assert state.scroll.offset_x == 0
        {:ok, Map.merge(context, %{before: nav_rows(), before_offset: state.scroll.offset_x})}
      end

      when_ "we click the track well to the right of its thumb", context do
        %{
          entry: %{
            screen_bounds: %{left: left, top: top, width: width, height: height}
          }
        } = SemanticProbe.dump({:scrollbar_x_track, :default})

        %{
          entry: %{
            screen_bounds: %{left: thumb_left, width: thumb_width}
          }
        } = SemanticProbe.dump({:scrollbar_x_thumb, :default})

        # Use the primitive's measured screen bounds and click halfway through
        # the actual empty segment. This also validates that the track and thumb
        # geometry published by the assembled graph agree.
        thumb_right = thumb_left + thumb_width
        track_right = left + width
        assert thumb_right < track_right
        click_x = thumb_right + (track_right - thumb_right) / 2
        # Child-graph semantic bounds are component-local in this Scenic
        # version. Project the measured track bounds through the SideNav frame.
        state = side_nav_state()
        click_y = state.frame.pin.y + top + height / 2
        {:ok, viewport} = Scenic.ViewPort.info(:main_viewport)

        Scenic.ViewPort.Input.send(
          viewport,
          {:cursor_button, {:btn_left, 1, [], {click_x, click_y}}}
        )

        Scenic.ViewPort.Input.send(
          viewport,
          {:cursor_button, {:btn_left, 0, [], {click_x, click_y}}}
        )

        Process.sleep(600)

        {:ok,
         Map.merge(context, %{track_bounds: {left, top, width, height}, click: {click_x, click_y}})}
      end

      then_ "the visible rows page left", context do
        after_rows = nav_rows()
        final_offset = side_nav_state().scroll.offset_x

        moved? =
          Enum.zip(context.before, after_rows)
          |> Enum.any?(fn {{id_a, _, left_a}, {id_b, _, left_b}} ->
            id_a == id_b and left_b < left_a
          end)

        assert final_offset > context.before_offset,
               "horizontal track click #{inspect(context.click)} in #{inspect(context.track_bounds)} did not change offset: #{context.before_offset} -> #{final_offset}"

        assert moved?,
               "horizontal offset moved to #{final_offset}, but rendered rows did not page left"

        {:ok, context}
      end
    end

    scenario "The final row clears the horizontal scrollbar" do
      given_ "a navigator overflowing on both axes", context do
        open_nav_overflowing()
        state = side_nav_state()
        assert state.scroll.content_width > state.scroll.viewport_width
        assert state.scroll.content_height > state.scroll.viewport_height
        {:ok, context}
      end

      when_ "we scroll to the very bottom", context do
        Probes.send_scroll(0, -10_000, @nav_x, @nav_y)
        Process.sleep(600)
        {:ok, context}
      end

      then_ "the last row ends above the horizontal scrollbar", context do
        state = side_nav_state()

        last_row_bottom =
          state.item_bounds
          |> Map.values()
          |> Enum.map(&(&1.y + &1.height))
          |> Enum.max()
          |> Kernel.-(state.scroll.offset_y)
          |> Kernel.+(state.frame.pin.y)

        # ScrollRenderer places its 12px bar 2px above the frame bottom.
        scrollbar_top = state.frame.pin.y + state.frame.size.height - 14

        assert last_row_bottom < scrollbar_top,
               "last row bottom #{last_row_bottom} overlaps scrollbar top #{scrollbar_top}"

        {:ok, context}
      end
    end
  end

  spex "The navigator's text is smaller than the editor's",
    description: "The sidebar is chrome and should not compete with the buffer text",
    tags: [:phase_27, :side_nav, :theme] do
    scenario "Nav font is derived from, and smaller than, the editor text size" do
      given_ "the editor's configured text size", context do
        %{text_size: text_size} = Quillex.RadixCache.ViewStore.get_state()
        {:ok, Map.put(context, :text_size, text_size)}
      end

      then_ "the navigator theme derives a strictly smaller font", context do
        theme = SideNavThemes.for_editor(context.text_size)

        assert theme.font_size < context.text_size,
               "nav font #{theme.font_size} should be smaller than editor text #{context.text_size}"

        # It scales with the editor rather than being pinned to one value...
        assert SideNavThemes.for_editor(32).font_size >
                 SideNavThemes.for_editor(16).font_size

        # ...but never shrinks into illegibility at the 12pt minimum.
        assert SideNavThemes.for_editor(12).font_size >= 11

        {:ok, context}
      end

      and_ "rendered rows are pitched tighter than the editor's text size", context do
        open_nav()

        pitch =
          case nav_rows(2) do
            [{_, top_a, _}, {_, top_b, _}] -> abs(top_b - top_a)
            other -> flunk("expected two nav rows to measure pitch, got #{inspect(other)}")
          end

        # Row pitch is font_size + 10; anything at or above the editor's own
        # text size means the nav is rendering at buffer scale again.
        assert pitch < context.text_size + 10,
               "nav row pitch #{pitch} suggests the nav is still rendering at editor text size #{context.text_size}"

        {:ok, context}
      end
    end
  end

  spex "The status label follows the cursor",
    description: "Ln/Col updates as the cursor moves, and sits evenly in its frame",
    tags: [:phase_27, :status_bar] do
    scenario "Moving the cursor updates Ln/Col" do
      given_ "a multi-line file is open and focused", context do
        # Leave the navigator closed so this scenario, and any spex file after
        # it, gets the ordinary full-width editor layout back.
        Quillex.RadixCache.ViewStore.close_file_nav()
        Process.sleep(600)

        Probes.send_keys("escape", [])
        Process.sleep(200)

        :ok =
          Quillex.TestHelpers.FileOpener.open_file(Path.expand("biblio/spinozas_ethics_p1.txt"))

        Process.sleep(900)

        frame = SemanticHelpers.get_buffer_frame()
        assert frame != nil, "buffer pane semantic frame not available"
        Probes.click(frame.x + trunc(frame.width * 0.3), frame.y + trunc(frame.height * 0.3))
        Process.sleep(400)

        # Go to a known origin so the assertion below is about movement,
        # not about wherever the click happened to land.
        Probes.send_keys("home", [:ctrl])
        Process.sleep(500)

        {:ok, Map.put(context, :before, cursor_label())}
      end

      when_ "we move the cursor down and right", context do
        for _ <- 1..3 do
          Probes.send_keys("down", [])
          Process.sleep(120)
        end

        for _ <- 1..2 do
          Probes.send_keys("right", [])
          Process.sleep(120)
        end

        Process.sleep(500)
        {:ok, context}
      end

      then_ "the label reports the new position", context do
        now = cursor_label()

        assert now != nil, "no 'Ln .., Col ..' label found on screen"

        assert now != context.before,
               """
               The cursor moved 3 lines down and 2 columns right, but the
               status label did not change.
               before: #{inspect(context.before)}
               after:  #{inspect(now)}
               """

        assert now =~ ~r/Ln 4, Col 3/,
               "expected the label to read Ln 4, Col 3 after the moves, got: #{inspect(now)}"

        {:ok, context}
      end
    end
  end

  # "Ln X, Col Y" is chrome, so it is deliberately excluded from
  # get_rendered_text_string/0 — read the unfiltered text instead.
  defp cursor_label do
    ScriptInspector.extract_rendered_text()
    |> List.flatten()
    |> Enum.find(fn t -> is_binary(t) and String.starts_with?(t, "Ln ") end)
  end
end
