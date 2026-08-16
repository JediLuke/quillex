defmodule Quillex.TestHelpers.ViewportResizer do
  @moduledoc """
  Injects a `{:viewport, {:reshape, {w, h}}}` input through Scenic's public
  input API — the same event the GLFW driver sends when the OS window is
  resized. This lets spex exercise the resize/reflow path deterministically,
  without needing a window manager to actually resize the window.

  Note: this does not resize the OS window itself; it drives the app's
  internal layout, which is exactly what the resize spex asserts on.
  """

  def resize(width, height) when is_number(width) and is_number(height) do
    {:ok, viewport} = Scenic.ViewPort.info(:main_viewport)
    Scenic.ViewPort.Input.send(viewport, {:viewport, {:reshape, {width, height}}})
  end

  @doc """
  The viewport's current size, `{width, height}`.

  Spex must NOT hardcode window-size-dependent coordinates: the WM may grant
  a smaller window than requested (and since the reflow fix the app adapts
  to whatever it gets), so edge-anchored UI like scrollbars sits at
  positions that depend on the actual size. Compute coordinates from this.
  """
  def viewport_size do
    {:ok, %Scenic.ViewPort{size: size}} = Scenic.ViewPort.info(:main_viewport)
    size
  end
end
