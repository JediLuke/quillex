defmodule Quillex.TestHelpers.Invariants do
  @moduledoc """
  Editor invariants — properties that must hold after ANY interaction
  (Roadmap 1.0, Phase 4b layer 1).

  `assert_invariants!/0` reads the buffer pane's semantic metadata and
  raises with a descriptive message if any invariant is violated. Sprinkle
  it into spex `then_` blocks (one line each) and every scenario doubles as
  an invariant check; property/fuzz spex can call it after every step.

  Current invariants (semantic-level — checkable today):

  1. **Cursor in document** — the cursor's line exists and its column is
     within [1, line_length + 1].
  2. **Scroll within content** — offsets are non-negative and do not
     exceed the scrollable range (content size minus viewport, plus a
     one-line slack for renderer rounding).
  3. **Sane frame** — the pane's rendered frame has positive dimensions.

  A fourth class — "cursor RENDERS inside the pane" (pixels, not state) —
  requires a transform-aware ScriptInspector and is tracked in Roadmap 4b.
  """

  alias Quillex.TestHelpers.SemanticHelpers

  @scroll_slack_px 30

  def assert_invariants! do
    case buffer_semantic() do
      nil ->
        # No buffer pane on screen (e.g. dialog-only states) — nothing to check
        :ok

      buffer ->
        semantic = buffer.semantic || %{}
        lines = String.split(buffer.content || "", "\n")

        check_cursor!(semantic[:cursor_position], lines)
        check_scroll!(semantic[:scroll])
        check_frame!(semantic[:frame])
        :ok
    end
  end

  defp check_cursor!(nil, _lines), do: :ok

  defp check_cursor!({line, col}, lines) do
    line_count = max(length(lines), 1)

    unless line >= 1 and line <= line_count do
      raise "INVARIANT VIOLATED: cursor line #{line} outside document (1..#{line_count})"
    end

    line_len = String.length(Enum.at(lines, line - 1) || "")

    unless col >= 1 and col <= line_len + 1 do
      raise "INVARIANT VIOLATED: cursor col #{col} outside line #{line} (1..#{line_len + 1})"
    end
  end

  defp check_scroll!(nil), do: :ok

  defp check_scroll!(%{offset_x: ox, offset_y: oy} = scroll) do
    unless ox >= 0 and oy >= 0 do
      raise "INVARIANT VIOLATED: negative scroll offset #{inspect({ox, oy})}"
    end

    max_y = max((scroll[:content_height] || 0) - (scroll[:viewport_height] || 0), 0)
    max_x = max((scroll[:content_width] || 0) - (scroll[:viewport_width] || 0), 0)

    unless oy <= max_y + @scroll_slack_px do
      raise "INVARIANT VIOLATED: offset_y #{oy} beyond scrollable range #{max_y} (+#{@scroll_slack_px} slack)"
    end

    unless ox <= max_x + @scroll_slack_px do
      raise "INVARIANT VIOLATED: offset_x #{ox} beyond scrollable range #{max_x} (+#{@scroll_slack_px} slack)"
    end
  end

  defp check_frame!(nil), do: :ok

  defp check_frame!(%{width: w, height: h}) do
    unless w > 0 and h > 0 do
      raise "INVARIANT VIOLATED: buffer pane frame has non-positive size #{inspect({w, h})}"
    end
  end

  defp buffer_semantic do
    case Scenic.ViewPort.info(:main_viewport) do
      {:ok, viewport} ->
        case SemanticHelpers.find_text_buffer(viewport) do
          {:ok, buffer} -> buffer
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
