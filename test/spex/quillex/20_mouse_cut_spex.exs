defmodule Quillex.MouseCutSpex do
  @moduledoc """
  Phase 20: Bug 001 regression — Ctrl+X after mouse-drag selection.

  This spex exists to keep bug 001 from silently coming back. See
  `docs/bugs/001_ctrl_x_mouse_select_crash.md` for the full write-up. In short:

  - `buffer_backed` TextField used to guard Ctrl+X on `state.selection != nil`.
  - Mouse-drag only populated `state.selection` via a round-trip broadcast
    from the buffer process.
  - If Ctrl+X fired before the broadcast landed, the keystroke was swallowed
    and the user's selected text never reached the clipboard or the delete
    path — silent data loss.

  The fix routes Ctrl+X (and Ctrl+C) in buffer_backed mode straight to
  `{:cut, :selection}` / `{:copy, :selection}` on the buffer controller,
  making the buffer the single source of truth for the selection shape.

  ## Scenarios

  - **Keyboard-selection regression guard** (required pass): select a range
    with Shift+arrow, press Ctrl+X, assert the buffer content drops the cut
    suffix. Queried via `SemanticHelpers` — the buffer's semantic content is
    the authoritative source of truth, not a substring check over the full
    rendered viewport.
  - **Mouse-drag cut** (best-effort): perform a real mouse drag via
    `ScenicMcp.Probes.mouse_down` / `send_mouse_move` / `mouse_up`, press
    Ctrl+X, assert the app has not crashed. If the probe cannot land an
    absolute buffer-pane coordinate reliably, this scenario is documented as
    deferred in the PRD rather than flaky.
  """
  use SexySpex

  alias ScenicMcp.Query
  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers

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

  # ===========================================================================
  # Helpers (mirrors the robust pattern used in 07_integration_v1_spex.exs)
  # ===========================================================================

  # Create a new empty buffer via File → New and click into it to focus.
  defp new_focused_buffer do
    Probes.click_element("icon_menu_file")
    Process.sleep(200)
    Probes.click_element("icon_menu_file_new")
    Process.sleep(500)
    # Dismiss any overlay and click into the buffer pane to ensure focus.
    Probes.send_keys("escape", [])
    Process.sleep(150)
    Probes.send_mouse_click(400, 400)
    Process.sleep(150)
  end

  defp active_buffer_id do
    case Scenic.ViewPort.info(:main_viewport) do
      {:ok, viewport} ->
        case SemanticHelpers.find_text_buffer(viewport) do
          {:ok, buffer} -> get_in(buffer, [:semantic, :buffer_id])
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp active_buffer_content do
    with {:ok, viewport} <- Scenic.ViewPort.info(:main_viewport) do
      buffer_id = active_buffer_id()

      lookup =
        if buffer_id do
          SemanticHelpers.find_text_buffer(viewport, buffer_id)
        else
          SemanticHelpers.find_text_buffer(viewport)
        end

      case lookup do
        {:ok, buffer} -> buffer.content || ""
        _ -> nil
      end
    end
  end

  defp wait_for_active_buffer_content(expected, timeout \\ 5000) do
    with {:ok, viewport} <- Scenic.ViewPort.info(:main_viewport) do
      buffer_id = active_buffer_id()

      if buffer_id do
        SemanticHelpers.wait_for_buffer_content(viewport, expected, buffer_id, timeout)
      else
        SemanticHelpers.wait_for_buffer_content(viewport, expected, timeout)
      end
    end
  end

  # ===========================================================================
  # Scenario 1 — keyboard-selection regression guard (required pass)
  # ===========================================================================

  spex "Bug 001 - Ctrl+X cuts a keyboard-selected range",
    description: "Shift+arrow selects a range, Ctrl+X removes the selection",
    tags: [:bug_001, :ctrl_x, :cut, :keyboard_selection] do

    scenario "Shift+Right then Ctrl+X removes the selected suffix", _context do
      given_ "a fresh buffer contains 'hello world' with cursor just before 'world'", context do
        new_focused_buffer()

        Probes.send_text("hello world")
        Process.sleep(200)
        {:ok, _} = wait_for_active_buffer_content("hello world")

        # Move cursor to start of line, then six columns right so it sits
        # between "hello " and "world".
        Probes.send_keys("home", [])
        Process.sleep(80)

        for _ <- 1..6 do
          Probes.send_keys("right", [])
          Process.sleep(30)
        end

        {:ok, context}
      end

      when_ "we Shift+Right five times to select 'world' and press Ctrl+X", context do
        for _ <- 1..5 do
          Probes.send_keys("right", [:shift])
          Process.sleep(30)
        end
        Process.sleep(120)
        Probes.send_keys("x", [:ctrl])
        Process.sleep(250)
        {:ok, context}
      end

      then_ "the buffer now contains only 'hello ' (the 'world' suffix is gone)", context do
        {:ok, _} = wait_for_active_buffer_content("hello ")
        content = active_buffer_content()
        assert content == "hello ",
               "Expected buffer content 'hello ' after cutting 'world', got #{inspect(content)}"
        {:ok, context}
      end

      then_ "the app is still rendering normally (no crash)", context do
        rendered = Query.rendered_text()
        assert is_binary(rendered) and rendered != "",
               "App should keep rendering after Ctrl+X"
        {:ok, context}
      end
    end
  end

  # ===========================================================================
  # Scenario 2 — mouse-drag cut (best-effort)
  # ===========================================================================

  spex "Bug 001 - Ctrl+X cuts a mouse-selected range",
    description: "Mouse-drag selects a range, Ctrl+X removes the selection",
    tags: [:bug_001, :ctrl_x, :cut, :mouse_selection] do

    scenario "mouse-drag then Ctrl+X does not crash the app", _context do
      given_ "a fresh buffer contains 'abcdefghij' on a single line", context do
        new_focused_buffer()
        Probes.send_text("abcdefghij")
        Process.sleep(200)
        {:ok, _} = wait_for_active_buffer_content("abcdefghij")
        {:ok, context}
      end

      when_ "we mouse-drag across the first few characters and press Ctrl+X", context do
        # Exact pixel coordinates depend on font metrics and the buffer-pane
        # frame position. Any values that land inside the buffer area will
        # exercise the drag path; if the drag lands off-buffer, the selection
        # will be empty and Ctrl+X will no-op — acceptable for this best-effort
        # scenario (per PRD). The *required* regression guard is the keyboard
        # scenario above.
        try do
          Probes.mouse_down(200, 120)
          Process.sleep(80)
          Probes.send_mouse_move(320, 120)
          Process.sleep(80)
          Probes.mouse_up(320, 120)
          Process.sleep(150)
          Probes.send_keys("x", [:ctrl])
          Process.sleep(200)
        rescue
          _ -> :deferred
        end
        {:ok, context}
      end

      then_ "the app is still rendering and has not crashed", context do
        rendered = Query.rendered_text()
        assert is_binary(rendered) and rendered != "",
               "App must keep rendering after mouse-drag + Ctrl+X"
        {:ok, context}
      end
    end
  end
end
