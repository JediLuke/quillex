defmodule Quillex.SyntaxHighlightingSpex do
  @moduledoc """
  Phase 42: structural syntax highlighting.

  An Elixir file's visible rows are drawn as runs in different faces of the
  mono family (bold keywords, semibold names, light heredocs, italic
  attributes/comments) with underlined strings — no colour involved. Plain
  text files stay plain; the View toggle switches it off and on.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset

  defp root_state, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

  defp pane_pid do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, :buffer_pane)
    pid
  end

  defp pane_state, do: :sys.get_state(pane_pid(), 30_000).assigns.state

  defp fonts_in_use do
    :sys.get_state(pane_pid(), 30_000).assigns.graph.primitives
    |> Map.values()
    |> Enum.filter(&(&1.module == Scenic.Primitive.Text))
    |> Enum.map(& &1.styles[:font])
    |> Enum.frequencies()
  end

  defp underlines do
    :sys.get_state(pane_pid(), 30_000).assigns.graph.primitives
    |> Map.values()
    |> Enum.count(&(&1.module == Scenic.Primitive.Line))
  end

  defp wait_until(predicate, timeout \\ 3_000) do
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

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()
    :ok
  end

  spex "Elixir source is highlighted structurally, plain text is not",
    description: "Weight, slant and underline mark token classes; the toggle turns it off",
    tags: [:phase_42, :syntax_highlighting] do
    scenario "opening an .ex file, a .txt file, and toggling" do
      when_ "an Elixir file is opened", context do
        unless root_state().syntax_highlighting,
          do: Quillex.RadixCache.ViewStore.toggle_syntax_highlighting()

        :ok = Quillex.TestHelpers.FileOpener.open_file(Path.expand("lib/highlight/highlight.ex"))

        assert wait_until(fn -> is_map(pane_state().highlights) end),
               "the highlight store should publish spans for the file"

        {:ok, context}
      end

      then_ "keywords, names, docs and attributes use distinct faces; strings are underlined",
            context do
        assert wait_until(fn -> Map.has_key?(fonts_in_use(), :ibm_plex_mono_bold) end)
        fonts = fonts_in_use()
        assert fonts[:ibm_plex_mono_bold] > 0, "keywords in bold: #{inspect(fonts)}"
        assert fonts[:ibm_plex_mono_semibold] > 0, "module/function names in semibold"
        assert fonts[:ibm_plex_mono_light] > 0, "the moduledoc heredoc in light"
        assert fonts[:ibm_plex_mono_medium_italic] > 0, "module attributes in medium italic"
        assert underlines() > 0, "strings underlined"
        Probes.take_screenshot("42_structural_highlighting")
        {:ok, context}
      end

      then_ "typing keeps the row honest until it is re-lexed", context do
        Probes.click(700, 300)
        Process.sleep(150)
        Probes.send_text("defmodule Typed do ")
        # the edited line is re-lexed and comes back highlighted
        assert wait_until(fn ->
                 case pane_state() do
                   %{highlights: %{1 => {text, _}}, lines: [first | _]} -> text == first
                   _ -> false
                 end
               end),
               "line 1's spans should be recomputed for its new text"

        {:ok, context}
      end

      then_ "the View toggle turns it off and back on", context do
        Probes.click_element("icon_menu_view")
        Process.sleep(200)
        Probes.click_element("icon_menu_view_syntax_highlighting")

        assert wait_until(fn -> not Map.has_key?(fonts_in_use(), :ibm_plex_mono_bold) end),
               "no bold runs once highlighting is off"

        refute root_state().syntax_highlighting

        # A toggle leaves the dropdown open; close it before reopening
        Probes.send_keys("escape", [])
        Process.sleep(200)
        Probes.click_element("icon_menu_view")
        Process.sleep(200)
        Probes.click_element("icon_menu_view_syntax_highlighting")
        assert wait_until(fn -> Map.has_key?(fonts_in_use(), :ibm_plex_mono_bold) end)
        {:ok, context}
      end

      then_ "a plain text file has no spans and no styled runs", context do
        :ok =
          Quillex.TestHelpers.FileOpener.open_file(
            Path.expand("test/support/spinozas_ethics_p1.txt")
          )

        assert wait_until(fn -> pane_state().highlights == nil end)
        refute Map.has_key?(fonts_in_use(), :ibm_plex_mono_bold)
        {:ok, context}
      end
    end
  end
end
