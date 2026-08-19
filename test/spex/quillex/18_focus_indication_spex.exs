defmodule Quillex.FocusIndicationSpex do
  @moduledoc """
  Phase 18: Focus Indication

  Validates that the buffer pane's border visibly indicates whether the editor
  currently has keyboard focus. This closes the last Executive Plan Phase 2
  Tier 2 item: users should be able to tell at a glance whether typing will
  land in the editor or the search bar.

  Colors (must match in both renderizer and BufferPane):
  - focused:   {255, 215, 0}      (amber/gold)
  - unfocused: {80, 80, 100, 180} (dim blue-grey)
  """
  use SexySpex

  alias ScenicMcp.Query
  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers

  @focused_border {255, 215, 0}
  @unfocused_border {80, 80, 100, 180}

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

  spex "Editor has focus border on startup",
    description: "Buffer pane renders the focused border color when the app starts and no overlay is open",
    tags: [:phase_18, :focus, :startup] do

    scenario "Buffer pane is focused on startup" do
      given_ "Quillex has just launched with no overlays", context do
        Process.sleep(300)
        # Dismiss anything that might have stolen focus (menus, search bar, etc.)
        Probes.send_keys("escape", [])
        Process.sleep(200)
        {:ok, context}
      end

      when_ "we query the buffer pane focus state", context do
        info = SemanticHelpers.buffer_pane_focus_info()
        {:ok, Map.put(context, :focus_info, info)}
      end

      then_ "the buffer pane reports focused? == true with the amber border", context do
        %{focus_info: info} = context

        assert info.focused? == true,
          "Buffer pane should be focused on startup, got: #{inspect(info)}"

        assert info.focused_border == @focused_border,
          "focused_border color should be #{inspect(@focused_border)}, got: #{inspect(info.focused_border)}"

        assert info.current_border == @focused_border,
          "Current border should be the focused amber color when focused, got: #{inspect(info.current_border)}"

        {:ok, context}
      end
    end
  end

  spex "Opening search bar transfers focus away from buffer",
    description: "Pressing Ctrl+F blurs the buffer pane and switches the border to the unfocused color",
    tags: [:phase_18, :focus, :search] do

    scenario "Ctrl+F moves focus out of the buffer pane" do
      given_ "Quillex is running and the buffer pane is focused", context do
        Process.sleep(300)
        Probes.send_keys("escape", [])
        Process.sleep(200)
        # Sanity check — buffer should own focus before we open search
        assert SemanticHelpers.buffer_pane_focused?() == true,
          "precondition: buffer pane must be focused before opening search"
        {:ok, context}
      end

      when_ "we press Ctrl+F", context do
        Probes.send_keys("f", [:ctrl])
        Process.sleep(500)
        {:ok, context}
      end

      then_ "buffer pane reports focused? == false, border is dim, and search bar is visible" do
        info = SemanticHelpers.buffer_pane_focus_info()

        assert info.focused? == false,
          "Buffer pane should lose focus when search bar opens, got: #{inspect(info)}"

        assert info.border == @unfocused_border,
          "border color should be #{inspect(@unfocused_border)}, got: #{inspect(info.border)}"

        assert info.current_border == @unfocused_border,
          "Current border should be the dim unfocused color, got: #{inspect(info.current_border)}"

        # Reuse the search-bar visibility check from 06_find_spex.exs
        visible_check =
          Query.text_visible?("Aa") or
            Query.text_visible?("0/0") or
            Query.text_visible?("Find")

        assert visible_check, "Search bar should be visible after Ctrl+F"
        :ok
      end
    end
  end

  spex "Escape restores focus to the buffer pane",
    description: "Dismissing the search bar returns focus (and the amber border) to the editor",
    tags: [:phase_18, :focus, :escape] do

    scenario "Escape after Ctrl+F restores buffer focus" do
      given_ "the search bar is open and the buffer pane has lost focus", context do
        Process.sleep(300)
        Probes.send_keys("escape", [])
        Process.sleep(200)
        Probes.send_keys("f", [:ctrl])
        Process.sleep(400)

        info = SemanticHelpers.buffer_pane_focus_info()

        assert info.focused? == false,
          "precondition: buffer pane must be unfocused while search bar is open, got: #{inspect(info)}"

        {:ok, context}
      end

      when_ "we press Escape", context do
        Probes.send_keys("escape", [])
        Process.sleep(400)
        {:ok, context}
      end

      then_ "buffer pane reports focused? == true and the amber border is restored" do
        info = SemanticHelpers.buffer_pane_focus_info()

        assert info.focused? == true,
          "Buffer pane should regain focus after Escape closes the search bar, got: #{inspect(info)}"

        assert info.current_border == @focused_border,
          "Current border should be the focused amber color after Escape, got: #{inspect(info.current_border)}"

        :ok
      end
    end
  end
end
