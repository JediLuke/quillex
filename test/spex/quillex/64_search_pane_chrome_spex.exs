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

  defp widget(id), do: Enum.find(State.header_widgets(pane_state()), &(&1.id == id))

  defp texts do
    pane_graph().primitives
    |> Map.values()
    |> Enum.filter(&(&1.module == Scenic.Primitive.Text))
    |> Enum.map(& &1.data)
  end

  defp status_text do
    Enum.find(texts(), &(&1 =~ ~r/^(\d+ in \d+ files?  \(\d+ms\)|no matches|searching…|typing…|Type to search|Search )/))
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
    File.write!(Path.join(root, "lib/a.ex"), "def needle(x), do: x\n")
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

        Probes.send_keys("f", [:ctrl, :shift])
        assert wait_until(fn -> pane_open?() end)

        Probes.click_element("search_pane_clear")
        Process.sleep(300)

        {:ok, context}
      end

      then_ "it says which project it is about to search", context do
        status = status_text()

        assert status && String.starts_with?(status, "Search "),
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

      then_ "the settings are a cog on the bar, not a row above it", context do
        cog = widget(:domain_header)
        view = widget(:results_view)
        status = widget(:status)

        assert cog, "there is no settings control at all"

        assert cog.y == status.y,
               "the cog belongs on the status bar (#{cog.y} vs #{status.y})"

        assert cog.x + cog.w <= view.x,
               "and beside the tree/list slider (#{cog.x + cog.w} vs #{view.x})"

        refute Enum.any?(texts(), &String.contains?(&1, "SEARCH SETTINGS")),
               "a whole row saying so is what the cog replaced: #{inspect(texts())}"

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
         |> Map.put(:header_before, State.header_height(pane_state()))}
      end

      when_ "the cog is clicked", context do
        Probes.click_element("search_pane_domain")
        Process.sleep(300)
        {:ok, context}
      end

      then_ "a panel drops out of the cog, and NOTHING moves", context do
        assert wait_until(fn -> pane_state().domain_open? end), "the cog did not open the settings"

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

        assert widget(:domain_header).y == context.status_before,
               "the cog moved out from under the pointer that clicked it"

        assert State.header_height(state) == context.header_before,
               """
               the header changed height, so the results moved
               (#{State.header_height(state)} vs #{context.header_before})
               """

        {:ok, context}
      end

      then_ "and it is drawn over the results, not among them", context do
        assert Scenic.Graph.get(pane_graph(), :search_pane_settings) != [],
               "the panel is not a piece of the graph of its own"

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

      when_ "the cog is clicked again", context do
        Probes.click_element("search_pane_domain")
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the panel goes away and still nothing has moved", context do
        assert wait_until(fn -> not pane_state().domain_open? end)

        assert Scenic.Graph.get(pane_graph(), :search_pane_settings) == [],
               "the panel outlived the click that shut it"

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
