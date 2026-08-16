defmodule Quillex.TestHelpers.Perf do
  @moduledoc """
  Boundary-exported access to `Quillex.PerfMonitor` for spex.

  Lets performance spex reset counters before a workload and read the
  rolling stats after, so render/handler budgets can be asserted as part
  of the suite (Roadmap 1.0, performance workstream).
  """

  defdelegate stats, to: Quillex.PerfMonitor
  defdelegate reset, to: Quillex.PerfMonitor
end
