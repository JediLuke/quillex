defmodule Quillex.PerformanceBudgetSpex do
  @moduledoc """
  Phase 24: Performance budget (Roadmap 1.0 — performance workstream)

  Measures editor responsiveness under a realistic workload (typing and
  scrolling in a large file) using `Quillex.PerfMonitor`'s rolling stats,
  and asserts hard budgets so a perf regression fails the suite instead of
  being discovered by feel ("the pane is updating very very slowly").

  The measured numbers are logged on every run, so budgets can be tightened
  as the data accumulates. Current budgets are deliberately generous — they
  are tripwires for order-of-magnitude regressions (e.g. a full-pane
  recreation sneaking into the keystroke hot path), not micro-benchmarks:

  - average handler time  < 33 ms   (~2 frames at 60fps)
  - maximum handler time  < 500 ms  (no single multi-hundred-ms stall)
  - average render time   < 16.7 ms (one 60fps frame)
  """
  use SexySpex

  alias ScenicMcp.Probes
  alias ScenicMcp.Query
  alias Quillex.TestHelpers.Perf
  require Logger

  @avg_handler_budget_ms 33
  @max_handler_budget_ms 500
  @avg_render_budget_ms 16.7

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(2000)

    # Known LAYOUT to start from (overlays dismissed, file navigator
    # closed) without touching buffers — an open navigator shifts the
    # editor pane 250px right and makes fixed-x clicks miss it.
    Quillex.TestHelpers.AppReset.reset_layout!()
    :ok
  end

  spex "Editing a large file stays within the performance budget",
    description: "Type and scroll in Spinoza; assert handler/render times stay within budget",
    tags: [:phase_24, :performance] do
    scenario "Typing and scrolling workload" do
      given_ "Spinoza is open and focused, counters reset", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)

        :ok =
          Quillex.TestHelpers.FileOpener.open_file(
            Path.expand("biblio/spinozas_ethics_p1.txt")
          )

        Process.sleep(800)
        assert Query.text_visible?("CONCERNING GOD")

        # Focus the pane, then start measuring from a clean slate
        Probes.click(400, 300)
        Process.sleep(300)
        Perf.reset()
        {:ok, context}
      end

      when_ "the user types a sentence and scrolls around", context do
        for ch <- String.graphemes("The quick brown fox jumps!") do
          Probes.send_text(ch)
          Process.sleep(30)
        end

        for _ <- 1..10 do
          Probes.send_scroll(0, -3, 400, 300)
          Process.sleep(40)
        end

        for _ <- 1..10 do
          Probes.send_scroll(0, 3, 400, 300)
          Process.sleep(40)
        end

        Process.sleep(300)
        {:ok, context}
      end

      then_ "handler and render times are within budget", context do
        stats = Perf.stats()
        # warning level so the numbers survive into the quiet-run log
        Logger.warning("[perf-budget] measured: #{inspect(stats)}")

        avg_handler = stats[:avg_handler_ms] || 0
        max_handler = stats[:max_handler_ms] || 0
        avg_render = stats[:avg_render_ms] || 0

        assert avg_handler < @avg_handler_budget_ms,
               "average handler time #{avg_handler}ms blew the #{@avg_handler_budget_ms}ms budget — " <>
                 "something expensive crept into the keystroke/scroll hot path"

        assert max_handler < @max_handler_budget_ms,
               "worst-case handler time #{max_handler}ms blew the #{@max_handler_budget_ms}ms budget"

        assert avg_render < @avg_render_budget_ms,
               "average GPU render time #{avg_render}ms blew the #{@avg_render_budget_ms}ms budget"

        Quillex.TestHelpers.Invariants.assert_invariants!()
        {:ok, context}
      end
    end
  end
end
