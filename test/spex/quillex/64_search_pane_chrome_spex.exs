defmodule Quillex.SearchPaneChromeSpex do
  @moduledoc """
  What the pane's controls look like, and where they sit.

  Three of these are things a font cannot be trusted with. IBM Plex Mono has
  no cog, no cancel sign and no disclosure triangle, and Scenic draws a
  missing glyph as an empty box — the same trap that made the menus spell
  "Cmd" instead of "⌘". So they are DRAWN, and this asserts on the shapes in
  the graph rather than on any string.

    * the settings are a cog on the status bar, beside the tree/list slider,
      rather than a whole row above it saying SEARCH SETTINGS;
    * clicking it opens a BOX above the bar, ruled off top and bottom, so
      that something on the screen connects the panel to the control that
      produced it;
    * clear is the cancel sign — a ring with a bar through it — rather than
      a third cross in a pane where a cross already means "dismiss this
      result" on every row and "close the pane" in the corner;
    * an empty pane names the project it is about to search.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias ScenicWidgets.SearchPane.State
  alias Quillex.TestHelpers.AppReset

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
  defp root_graph, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.graph

  defp widget(id), do: Enum.find(State.header_widgets(pane_state()), &(&1.id == id))

  defp texts do
    pane_graph().primitives
    |> Map.values()
    |> Enum.filter(&(&1.module == Scenic.Primitive.Text))
    |> Enum.map(& &1.data)
  end

  defp status_text do
    Enum.find(
      texts(),
      &(&1 =~ ~r/^(\d+ of \d+|no matches|searching…|typing…|Type to search|Search [~\/…])/)
    )
  end

  # Shapes drawn inside a rectangle — how a control made of primitives is
  # checked, since it has no text to read.
  defp shapes_within(%{x: x, y: y, w: w, h: h}) do
    pane_graph().primitives
    |> Map.values()
    |> Enum.filter(fn p ->
      case Map.get(p.transforms, :translate) do
        {px, py} -> px >= x - 2 and px <= x + w + 2 and py >= y - 2 and py <= y + h + 2
        _ -> false
      end
    end)
  end

  defp circles_within(bounds),
    do: Enum.filter(shapes_within(bounds), &(&1.module == Scenic.Primitive.Circle))

  defp lines_anywhere do
    pane_graph().primitives
    |> Map.values()
    |> Enum.filter(&(&1.module == Scenic.Primitive.Line))
  end

  # Anything in the settings panel drawn in the hover colour.
  defp hovered_fills do
    theme = ScenicWidgets.SearchPane.State.dropdown_theme(pane_state())
    want = theme.item_hover_bg

    case Scenic.Graph.get(pane_graph(), :search_pane_settings) do
      [panel] ->
        panel
        |> descendants(pane_graph())
        |> Enum.filter(fn p ->
          case Scenic.Primitive.get_style(p, :fill) do
            {:color, {:color_rgba, {r, g, b, _a}}} -> {r, g, b} == want
            _ -> false
          end
        end)
        # The either/or control fills its ACTIVE position in the same accent.
        # That is a selection, not a hover, and counting it would make every
        # assertion here one too many.
        |> Enum.reject(&match?({:segmented_thumb, _}, Map.get(&1, :id)))

      _ ->
        []
    end
  end

  defp descendants(%{module: Scenic.Primitive.Group, data: uids}, graph) do
    Enum.flat_map(uids, fn uid ->
      case Map.get(graph.primitives, uid) do
        nil -> []
        child -> descendants(child, graph)
      end
    end)
  end

  defp descendants(primitive, _graph), do: [primitive]

  defp semantic_entry(id) do
    viewport = :sys.get_state(Process.whereis(QuillEx.RootScene)).viewport

    case :ets.lookup(viewport.semantic_index, String.to_atom(id)) do
      [{_id, key}] ->
        case :ets.lookup(viewport.semantic_table, key) do
          [{_key, entry}] -> entry
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp scope_node_ids do
    scope_entries()
    |> Enum.map(fn {id, _} -> to_string(id) end)
    |> Enum.sort()
  end

  defp scope_entries do
    viewport = :sys.get_state(Process.whereis(QuillEx.RootScene)).viewport

    :ets.match_object(viewport.semantic_table, {{:search_pane, :_}, :_})
    |> Enum.map(fn {{_, id}, entry} -> {id, entry} end)
    |> Enum.filter(fn {id, _} ->
      id = to_string(id)

      String.starts_with?(id, "search_pane_scope_") and
        not String.starts_with?(id, "search_pane_scope_expand_")
    end)
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

  # The settings panel's scrollbar: drawn only when there is something to
  # scroll, so its presence IS the assertion.
  defp settings_thumb do
    case Scenic.Graph.get(pane_graph(), {:scrollbar_y_thumb, :search_pane_settings}) do
      [thumb] -> thumb
      _ -> nil
    end
  end

  # Where to press to grab it, in screen coordinates. The bar is drawn inside
  # the panel group, inset by the same padding `ScrollRenderer` uses for every
  # other bar in the editor.
  defp settings_thumb_centre do
    thumb = settings_thumb()
    {_w, h, _r} = thumb.data
    {_tx, ty} = Map.fetch!(thumb.transforms, :translate)

    layout = State.settings_layout(pane_state())
    {pin_x, pin_y} = pane_state().frame.pin.point
    inset = Widgex.Scroll.ScrollRenderer.inset()
    pad = Widgex.Scroll.ScrollRenderer.padding()

    {trunc(pin_x + layout.x + layout.width - inset / 2),
     trunc(pin_y + layout.y + pad + ty + h / 2)}
  end

  # More directories than the settings panel can show at once, so that
  # reaching the ones past its bottom edge is a thing this can test at all.
  @scope_dirs 60

  defp write_fixture(root) do
    File.rm_rf!(root)
    File.mkdir_p!(Path.join(root, "lib"))
    File.write!(Path.join(root, "lib/a.ex"), "def needle(x), do: x\n")

    Enum.each(1..@scope_dirs, fn i ->
      dir = Path.join(root, "pkg_#{String.pad_leading("#{i}", 2, "0")}")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "mod.ex"), "# needle #{i}\n")
    end)

    :ok
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    root = Path.join(System.tmp_dir!(), "quillex_search_pane_chrome")
    write_fixture(root)

    on_exit(fn ->
      Quillex.RadixCache.ViewStore.set_file_nav_path(File.cwd!())
      Process.sleep(200)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  spex "The pane's chrome says what it does without spelling it",
    description: "A cog, a cancel sign, a boxed settings panel, and a named project",
    tags: [:phase_41, :project_search, :search_pane, :chrome] do
    scenario "an empty pane" do
      given_ "the pane open on a project, with nothing typed", context do
        write_fixture(context.root)
        AppReset.reset!()
        Quillex.RadixCache.ViewStore.set_file_nav_path(context.root)
        Process.sleep(400)

        # Opening the pane is what points the search at the navigator's
        # directory, so the root can only be checked afterwards.
        Probes.send_keys("f", [:ctrl, :shift])
        assert wait_until(fn -> pane_open?() end)

        assert wait_until(fn ->
                 Quillex.RadixCache.ProjectSearchStore.get_state().root == context.root
               end),
               "opening the pane did not point the search at this project"

        Probes.click_element("search_pane_clear")
        Process.sleep(300)

        {:ok, context}
      end

      then_ "it says which project it is about to search", context do
        status = status_text()

        assert status && status =~ ~r/^Search [~\/…]/,
               """
               an empty pane described what searching is — true of every
               project there has ever been. It should name the one in front of
               you: #{inspect(status)}
               """

        # The pane is narrow, so a long path is clipped from the FRONT — the
        # end of it is the half that says which project this is.
        tail = context.root |> Path.basename() |> String.slice(-12..-1//1)

        assert String.contains?(status, tail),
               "and it should be THIS project: #{inspect(status)}"

        {:ok, context}
      end

      then_ "its file names are the size the file navigator draws them", context do
        # The two share the sidebar slot and list the same kind of thing. The
        # pane used to size its own text — 13pt against the navigator's 17 —
        # and the two read as different applications in the same strip.
        pane = pane_state().theme
        nav = Quillex.Utils.SideNavThemes.for_editor(24, Quillex.GUI.Palette.get(:dark))

        assert pane.font_size == nav.font_size,
               """
               a result's file name is #{pane.font_size}pt where the navigator
               would draw it #{nav.font_size}pt.
               """

        assert pane.row_height == nav.item_height,
               """
               and its rows are #{pane.row_height} tall against the
               navigator's #{nav.item_height}.
               """

        {:ok, context}
      end

      then_ "and everything else in the pane is measured from that", context do
        theme = pane_state().theme
        alias ScenicWidgets.SearchPane.State, as: S

        # These were pixels chosen against an 11pt label. A slider that cannot
        # hold the word "tree" is what a fixed width becomes the moment the
        # chrome is zoomed.
        assert S.slider_width(theme) >= 2 * round(4 * theme.small_font_size * 0.6),
               "the tree/list slider is too narrow for its own labels"

        assert S.button_size(theme) < theme.row_height,
               "a square control on the bar should sit inside the row it is on"

        assert theme.small_font_size < theme.font_size,
               "secondary type should be a step down from the results, not equal to them"

        {:ok, context}
      end

      then_ "the settings are a cog on the bar, not a row above it", context do
        cog = widget(:domain_header)
        clear = widget(:clear)
        status = widget(:status)

        assert cog, "there is no settings control at all"

        # INSIDE the bar's row, not sharing its exact y. The cog and the clear
        # button are square now, and a square control shorter than the row it
        # sits on has to be centred in it — the row is the assertion, and the
        # y they used to have in common was a coincidence of their being the
        # full height of it.
        assert cog.y >= status.y and cog.y + cog.h <= status.y + status.h,
               """
               the cog belongs on the status bar: it spans #{cog.y}..#{cog.y + cog.h}
               and the bar is #{status.y}..#{status.y + status.h}
               """

        assert cog.x + cog.w <= clear.x,
               "beside the clear button (#{cog.x + cog.w} vs #{clear.x})"

        refute Enum.any?(texts(), &String.contains?(&1, "SEARCH SETTINGS")),
               "a whole row saying so is what the cog replaced: #{inspect(texts())}"

        # And the tree/list control is NOT on the bar any more. It took a
        # third of a narrow bar to say something you change rarely.
        refute widget(:results_view),
               "the view control is still on the status bar"

        refute Enum.any?(texts(), &(&1 in ["tree", "list"])),
               "and its labels are still drawn there: #{inspect(texts())}"

        {:ok, context}
      end

      then_ "the cog is drawn, not typed", context do
        # A ring with spokes. Typed as U+2699 this would be an empty box.
        assert length(circles_within(widget(:domain_header))) >= 1,
               "the cog has no ring in it — is it a glyph?"

        {:ok, context}
      end

      then_ "and clear is the cancel sign rather than a third cross", context do
        clear = widget(:clear)

        assert length(circles_within(clear)) == 1,
               """
               clear should be a ring with a bar through it. A bare cross is
               already what × means on every result row and in the corner.
               """

        {:ok, context}
      end
    end

    scenario "opening the settings" do
      given_ "the settings shut", context do
        assert pane_state().domain_open? == false

        {:ok,
         context
         |> Map.put(:status_before, widget(:status).y)
         |> Map.put(:cog_before, widget(:domain_header).y)
         |> Map.put(:header_before, State.header_height(pane_state()))}
      end

      when_ "the cog is clicked", context do
        Probes.click_element("search_pane_domain")
        Process.sleep(300)
        {:ok, context}
      end

      then_ "a panel drops out of the cog, and NOTHING moves", context do
        assert wait_until(fn -> pane_state().domain_open? end),
               "the cog did not open the settings"

        state = pane_state()
        panel = State.settings_frame(state)
        {_px, py} = panel.pin.point

        assert State.settings_height(state) > 0, "the panel has no height"

        assert py >= widget(:status).y + widget(:status).h - 2,
               "the panel hangs below the bar the cog is on (#{py} vs #{widget(:status).y})"

        # This is the whole point. Every inline arrangement moved something:
        # above the bar it pushed the cog down out from under the pointer that
        # had just clicked it, below the bar it shoved the results about.
        assert widget(:status).y == context.status_before,
               "the bar moved (#{widget(:status).y} vs #{context.status_before})"

        assert widget(:domain_header).y == context.cog_before,
               "the cog moved out from under the pointer that clicked it"

        assert State.header_height(state) == context.header_before,
               """
               the header changed height, so the results moved
               (#{State.header_height(state)} vs #{context.header_before})
               """

        {:ok, context}
      end

      then_ "the view control is in there, as an either/or", context do
        # It is a Menu.Model.Segmented row now — a reusable one, so the next
        # thing needing a two-position control does not draw its own.
        assert semantic_entry("search_pane_view"),
               "the tree/list control did not move into the settings"

        for position <- ["tree", "list"] do
          assert semantic_entry("search_pane_view_#{position}"),
                 """
                 each position needs its own name, or choosing one is
                 arithmetic on which half of a control to aim at.
                 """
        end

        {:ok, context}
      end

      then_ "and it is drawn over the results, not among them", context do
        assert Scenic.Graph.get(pane_graph(), :search_pane_settings) != [],
               "the panel is not a piece of the graph of its own"

        assert Scenic.Graph.get(root_graph(), :file_nav_resize_handle_group) == [],
               "the root-owned resize handle must not draw over the settings panel"

        {:ok, context}
      end

      then_ "and it sits ON the results rather than seeping through them", context do
        [panel] = Scenic.Graph.get(pane_graph(), :search_pane_settings)

        body =
          panel.data
          |> Enum.map(&Map.get(pane_graph().primitives, &1))
          |> Enum.find(fn p ->
            p && p.module == Scenic.Primitive.RoundedRectangle &&
              Scenic.Primitive.get_style(p, :stroke)
          end)

        assert body,
               """
               a floating panel needs a body to sit on and an edge to end at,
               or the rows underneath read straight through it. Rounded and
               bordered, the same shape IconMenu gives its dropdown.
               """

        assert Scenic.Primitive.get_style(body, :fill),
               "it is transparent, so the results show through it"

        {_w, _h, radius} = body.data

        assert radius > 0,
               "a menu panel has rounded corners; this one has #{inspect(radius)}"

        {:ok, context}
      end

      when_ "the pointer moves onto one of the settings rows", context do
        entry = semantic_entry("search_pane_domain_use_ignore_files")
        assert entry, "the settings row publishes no position"

        %{left: l, top: t, width: w, height: h} = entry.screen_bounds
        Probes.send_mouse_move(trunc(l + w / 2), trunc(t + h / 2))
        Process.sleep(250)

        {:ok, context}
      end

      then_ "it lights up, the way a menu row does", context do
        assert hovered_fills() != [],
               """
               nothing in the panel changed colour under the pointer. Sharing
               the menubar's dropdown is supposed to bring its behaviour with
               it, not just its shape — a row that gives no sign it is a row
               is one people click twice to check.
               """

        {:ok, context}
      end

      when_ "the pointer moves onto a directory in the scope tree", context do
        Probes.click_element("search_pane_scope")
        assert wait_until(fn -> pane_state().scope_open? end), "the scope tree would not open"

        entry =
          Enum.find_value(scope_entries(), fn {id, e} ->
            if String.ends_with?(to_string(id), "/lib"), do: e
          end)

        assert entry,
               "no scope node to hover: #{inspect(Enum.map(scope_entries(), &elem(&1, 0)))}"

        %{left: l, top: t, width: w, height: h} = entry.screen_bounds
        Probes.send_mouse_move(trunc(l + w / 2), trunc(t + h / 2))
        Process.sleep(250)

        {:ok, Map.put(context, :node_top, entry.local_bounds.top)}
      end

      then_ "that ONE directory lights, not the whole tree", context do
        fills = hovered_fills()

        refute fills == [], "hovering a directory in the tree lit nothing"

        assert length(fills) == 1,
               """
               a tree is one menu ROW holding many, so lighting the row lights
               the whole tree. Only the node under the pointer should light:
               #{length(fills)} things did.
               """

        {:ok, context}
      end

      when_ "the scope tree is open on a project with many directories", context do
        unless pane_state().scope_open? do
          Probes.click_element("search_pane_scope")
          assert wait_until(fn -> pane_state().scope_open? end), "the scope tree would not open"
        end

        {:ok, context}
      end

      then_ "the panel is clamped to the pane, and draws a bar to say so", context do
        layout = State.settings_layout(pane_state())

        assert ScenicWidgets.Menu.Dropdown.scrollable?(layout),
               """
               this project has #{@scope_dirs} directories in it precisely so
               that the panel cannot show them all at once. It fits
               (#{layout.content_height} in #{layout.height}), so nothing below
               this proves anything.
               """

        assert layout.y + layout.height <= pane_state().frame.size.height,
               """
               the panel reaches #{trunc(layout.y + layout.height - pane_state().frame.size.height)}px
               past the bottom of the pane. A row below the edge cannot be
               clicked, so it may as well not be in the panel.
               """

        assert settings_thumb(),
               """
               the panel clamps and scrolls and says nothing about it. A menu
               that hides its own tail behind a silent offset is a menu whose
               last rows can be counted and never reached — which is the whole
               reason this bar exists.
               """

        assert pane_state().settings_scroll == 0,
               "a panel opens at its top, whatever the last visit left it at"

        {:ok, Map.put(context, :first_nodes, scope_node_ids())}
      end

      when_ "the wheel is turned over the panel", context do
        panel = ScenicWidgets.SearchPane.State.settings_frame(pane_state())
        {px, py} = panel.pin.point
        {pin_x, pin_y} = pane_state().frame.pin.point

        Enum.each(1..4, fn _ ->
          Probes.send_scroll(
            0,
            -1,
            trunc(pin_x + px + panel.size.width / 2),
            trunc(pin_y + py + panel.size.height / 2)
          )

          Process.sleep(80)
        end)

        {:ok, context}
      end

      then_ "the panel moves, and shows directories it could not before", context do
        assert wait_until(fn -> pane_state().settings_scroll > 0 end),
               "the wheel over the settings panel did not move it"

        now = scope_node_ids()

        refute MapSet.equal?(MapSet.new(now), MapSet.new(context.first_nodes)),
               """
               the same directories are published after scrolling past them.
               A panel that names rows it has wound off its own edge offers a
               click that lands on the document behind the pane.
               """

        {:ok, context}
      end

      then_ "and the results underneath did NOT move", context do
        # The wheel belongs to whatever is under it. With the panel over the
        # results, scrolling it must not slide the results about behind it.
        assert pane_state().scroll.offset_y == 0,
               "the results scrolled while the pointer was over the settings"

        {:ok, context}
      end

      when_ "it is wound all the way down", context do
        panel = ScenicWidgets.SearchPane.State.settings_frame(pane_state())
        {px, py} = panel.pin.point
        {pin_x, pin_y} = pane_state().frame.pin.point

        Enum.each(1..40, fn _ ->
          Probes.send_scroll(
            0,
            -1,
            trunc(pin_x + px + panel.size.width / 2),
            trunc(pin_y + py + panel.size.height / 2)
          )
        end)

        Process.sleep(400)
        {:ok, context}
      end

      then_ "the last directory in the project can be reached", context do
        last = "pkg_#{String.pad_leading("#{@scope_dirs}", 2, "0")}"

        assert Enum.any?(scope_node_ids(), &String.ends_with?(&1, last)),
               """
               the end of the tree cannot be reached, so a directory below the
               panel's bottom edge can be counted and never excluded:
               #{inspect(scope_node_ids())}
               """

        {:ok, context}
      end

      when_ "the panel is wound back to the top and its thumb dragged down", context do
        panel = State.settings_frame(pane_state())
        {px, py} = panel.pin.point
        {pin_x, pin_y} = pane_state().frame.pin.point

        Enum.each(1..60, fn _ ->
          Probes.send_scroll(
            0,
            1,
            trunc(pin_x + px + panel.size.width / 2),
            trunc(pin_y + py + panel.size.height / 2)
          )
        end)

        Process.sleep(400)

        assert wait_until(fn -> pane_state().settings_scroll == 0 end),
               "the wheel would not wind the panel back up again"

        {x, y} = settings_thumb_centre()
        Probes.mouse_down(x, y)
        Process.sleep(120)

        # In steps, the way a hand does it — a single jump would not catch a
        # handler that only works from where the press happened.
        Enum.each(1..5, fn i ->
          Probes.send_mouse_move(x, y + i * 25)
          Process.sleep(60)
        end)

        {:ok, Map.put(context, :drag_to, {x, y + 125})}
      end

      then_ "the panel follows it", context do
        assert wait_until(fn -> pane_state().settings_scroll > 0 end),
               """
               the bar can be looked at and not moved. This pane has shipped
               that exact bug once already — three drag fields on the state
               and no code reading them — so it is asserted rather than
               assumed.
               """

        {:ok, context}
      end

      when_ "the button is released and the pointer moves on", context do
        {x, y} = context.drag_to
        Probes.mouse_up(x, y)
        Process.sleep(150)

        settled = pane_state().settings_scroll

        Probes.send_mouse_move(x, y + 150)
        Process.sleep(200)

        {:ok, Map.put(context, :settled, settled)}
      end

      then_ "nothing more moves, because the drag is over", context do
        assert pane_state().settings_scroll == context.settled,
               "the panel went on following a pointer that had let go of it"

        {:ok, context}
      end

      when_ "the cog is clicked again", context do
        Probes.click_element("search_pane_domain")
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the panel goes away and still nothing has moved", context do
        assert wait_until(fn -> not pane_state().domain_open? end)

        assert Scenic.Graph.get(pane_graph(), :search_pane_settings) == [],
               "the panel outlived the click that shut it"

        assert Scenic.Graph.get(root_graph(), :file_nav_resize_handle_group) != [],
               "the resize handle should return when the overlapping panel closes"

        assert widget(:status).y == context.status_before,
               "the bar has not moved through any of this, which is the point"

        assert State.header_height(pane_state()) == context.header_before

        {:ok, context}
      end

      when_ "it is opened again and a click lands away from it", context do
        Probes.click_element("search_pane_domain")
        assert wait_until(fn -> pane_state().domain_open? end)

        # On the query field, which is nowhere near the panel.
        Probes.click_element("search_pane_field_query")
        Process.sleep(300)

        {:ok, context}
      end

      then_ "it closes, the way a menu does", context do
        assert wait_until(fn -> not pane_state().domain_open? end),
               "a menu left open behind whatever you clicked next is in the way"

        {:ok, context}
      end
    end
  end
end
