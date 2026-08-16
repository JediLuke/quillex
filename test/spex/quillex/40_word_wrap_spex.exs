defmodule Quillex.WordWrapSpex do
  @moduledoc "Proves that the View toggle performs word-aware wrapping through the real UI."
  use SexySpex

  alias Quillex.TestHelpers.{AppReset, SemanticProbe}
  alias ScenicMcp.Probes
  alias ScenicWidgets.TextField.Renderer

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    long_token = String.duplicate("identifier", 120)

    {:ok, buffer} =
      Quillex.Buffer.new(%{name: "word-wrap-proof.txt", data: ["alpha beta #{long_token} omega"]})

    :ok = Quillex.Buffer.activate(buffer)
    Process.sleep(300)
    {:ok, long_token: long_token}
  end

  spex "Word Wrap uses word boundaries and safely wraps oversized tokens",
    description:
      "The real View-menu toggle changes layout and keeps all wrapped content reachable",
    tags: [:phase_40, :view_settings, :word_wrap] do
    scenario "Enabling Word Wrap on prose containing a very long identifier" do
      when_ "Word Wrap is enabled through the View menu", context do
        unless pane_state().wrap_mode == :word do
          Probes.click_element("icon_menu_view")
          Process.sleep(100)
          Probes.click_element("icon_menu_view_word_wrap")
          Process.sleep(300)
        end

        {:ok, context}
      end

      then_ "the pane wraps vertically without horizontal overflow", context do
        state = pane_state()
        assert state.wrap_mode == :word
        assert state.scroll.content_width == state.scroll.viewport_width

        source_col = String.length("alpha beta #{context.long_token} omega") + 1
        {display_line, _display_col} = Renderer.source_to_display_cursor(state, {1, source_col})
        assert display_line > 1
        {:ok, context}
      end

      then_ "the menu remains semantically available as Word Wrap", context do
        assert %{entry: %{label: "Word Wrap"}} = SemanticProbe.dump(:icon_menu_view_word_wrap)
        {:ok, context}
      end
    end
  end

  spex "A wrapped scroll flood cannot starve a buffer switch",
    description:
      "Rapid wheel input remains bounded and a newly activated document replaces the pane promptly",
    tags: [:phase_40, :view_settings, :word_wrap, :performance] do
    scenario "Switching documents immediately after sustained wrapped scrolling" do
      given_ "a large wrapped document", context do
        lines =
          for n <- 1..1_200,
              do:
                "#{n}: reason and necessity extend this deliberately long line across the editor viewport " <>
                  String.duplicate("substance ", 12)

        {:ok, source} = Quillex.Buffer.new(%{name: "wrapped-scroll-flood.txt", data: lines})
        :ok = Quillex.Buffer.activate(source)
        Process.sleep(250)

        unless pane_state().wrap_mode == :word do
          Probes.click_element("icon_menu_view")
          Process.sleep(100)
          Probes.click_element("icon_menu_view_word_wrap")
          Process.sleep(250)
        end

        {:ok, Map.put(context, :source, source)}
      end

      when_ "one thousand wheel events are followed immediately by a buffer activation",
            context do
        for _ <- 1..1_000, do: Probes.send_scroll(0, -12, 500, 300)

        {:ok, target} =
          Quillex.Buffer.new(%{
            name: "post-scroll-target.txt",
            data: ["POST SCROLL TARGET IS VISIBLE"]
          })

        started = System.monotonic_time(:millisecond)
        :ok = Quillex.Buffer.activate(target)

        {:ok, Map.merge(context, %{target: target, switch_started: started})}
      end

      then_ "the TextField drains the input and renders the target within two seconds", context do
        assert wait_until(fn -> pane_state().buffer_id == context.target.uuid end, 2_000),
               "the TextField remained backlogged after the wrapped scroll flood"

        elapsed = System.monotonic_time(:millisecond) - context.switch_started
        assert elapsed < 2_000
        assert "POST SCROLL TARGET IS VISIBLE" in pane_state().lines
        {:ok, context}
      end
    end
  end

  defp pane_state do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :buffer_pane)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid).assigns.state
  end

  defp wait_until(predicate, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(predicate, deadline)
  end

  defp do_wait_until(predicate, deadline) do
    if predicate.() do
      true
    else
      if System.monotonic_time(:millisecond) >= deadline do
        false
      else
        Process.sleep(20)
        do_wait_until(predicate, deadline)
      end
    end
  end
end
