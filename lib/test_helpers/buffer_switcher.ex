defmodule Quillex.TestHelpers.BufferSwitcher do
  @moduledoc """
  Deterministic buffer switching for spex.

  Spex prefer UI-driven interaction, and buffer switching is normally done by
  clicking a tab. But a click can be lost (see the roadmap's input-drop
  notes), and a silently-failed switch is corrosive: every subsequent
  assertion in the scenario then tests the wrong document, usually surfacing
  as an unrelated-looking failure much later.

  This helper is the escape hatch: scenarios whose SUBJECT is the tab bar
  should still click, but scenarios that merely need to *be* on a given
  buffer can switch deterministically here (or fall back to it after a
  click fails).
  """

  @doc "Switch to the buffer at 1-based index `n` (tab order)."
  def switch(n) when is_integer(n) and n >= 1 do
    Quillex.Buffer.switch(n)
  end
end
