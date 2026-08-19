defmodule Quillex.MenuCloseOutsideClickSpex do
  @moduledoc """
  Phase 13: Menu Close-on-Outside-Click

  Validates that open menus and overlays close when the user clicks outside them:
  - Icon menu dropdown closes when clicking in the editor area
  - Search bar closes when clicking below it in the buffer area
  - File picker closes when clicking outside the modal dialog (already handled, regression)
  - Escape key still closes menus (regression test)

  Root cause addressed: the root scene now requests :cursor_button input and
  dispatches {:close_menu} to the IconMenu / calls hide_search_bar/1 when the
  click is in the editor area.
  """
  use SexySpex

  alias ScenicMcp.Query
  alias ScenicMcp.Probes

  defp root_state, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    # Wait for the scene to fully initialise
    Process.sleep(2000)

    # Known LAYOUT to start from (overlays dismissed, file navigator
    # closed) without touching buffers — an open navigator shifts the
    # editor pane 250px right and makes fixed-x clicks miss it.
    Quillex.TestHelpers.AppReset.reset_layout!()
    :ok
  end

  # ---------------------------------------------------------------------------
  # 1. Icon menu dropdown — close on outside click
  # ---------------------------------------------------------------------------

  spex "Icon Menu Dropdown Closes on Outside Click",
    description: "Clicking in the editor while the File dropdown is open closes the dropdown",
    tags: [:phase_13, :icon_menu, :close_on_outside_click] do

    scenario "File menu dropdown disappears after clicking in the editor" do
      given_ "the File dropdown is open", context do
        # Ensure a clean initial state
        Probes.send_keys("escape", [])
        Process.sleep(200)

        # Click the File icon to open the dropdown
        Probes.click_element("icon_menu_file")
        Process.sleep(400)

        # Confirm the dropdown is visible — "New Buffer" is only rendered
        # when the dropdown is open (renderer.ex skips it when active_menu == nil)
        assert Query.text_visible?("New Buffer"),
          "File dropdown should be open and show 'New Buffer'"
        {:ok, context}
      end

      when_ "we click far left in the editor area", context do
        # x=100 is well outside the dropdown x-range (which starts ~515px from
        # the left on a typical 800px-wide viewport).  y=200 is below the top bar.
        Probes.click(100, 200)
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the File menu dropdown should be closed" do
        # Dropdown items are only in the Scenic graph when active_menu != nil.
        # After close, "New Buffer" text should no longer be visible.
        refute Query.text_visible?("New Buffer"),
          "File dropdown should be closed after clicking outside it"
        :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Search bar — close on outside click
  # ---------------------------------------------------------------------------

  spex "Search Bar Survives an Outside Click",
    description: "Clicking in the editor hands the keyboard back WITHOUT closing the bar",
    tags: [:phase_13, :search_bar, :close_on_outside_click] do
    scenario "the find bar stays up when the user clicks into the document" do
      given_ "the search bar is open over a document", context do
        {:ok, buf} =
          Quillex.Buffer.new(%{name: "outside.txt", data: ["outside click test content"]})

        :ok = Quillex.Buffer.activate(buf)
        Process.sleep(400)
        Quillex.TestHelpers.Integration.close_search_bar_if_open()
        Quillex.TestHelpers.Integration.ensure_editor_focused()
        Process.sleep(200)

        Probes.send_keys("f", [:ctrl])
        Process.sleep(600)

        assert root_state().show_search_bar, "Ctrl+F should open the bar"
        {:ok, context}
      end

      when_ "we click in the buffer area below the search bar", context do
        Probes.click(400, 200)
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the bar is still there", context do
        # This spex used to assert the opposite, and it passed for a reason
        # that had nothing to do with closing: the old bar consumed codepoints
        # whether or not it had focus, so the typed character reached the
        # document either way and "the bar must have closed" was never tested.
        #
        # Clicking into the document while a search is up means "let me edit
        # for a moment", not "throw the search away". Escape closes the bar,
        # and so does its own X.
        assert root_state().show_search_bar,
               "a click in the document must not close the find bar"

        {:ok, context}
      end

      then_ "and the keystrokes go to the editor", context do
        {:ok, before} = Quillex.Buffer.fetch(root_state().active_buf)

        Probes.send_text("Q")
        Process.sleep(400)

        {:ok, after_typing} = Quillex.Buffer.fetch(root_state().active_buf)

        assert after_typing.lines != before.lines,
               "typing after the click should reach the document, not the query field"

        {:ok, context}
      end

      then_ "and Escape is what closes it", context do
        Probes.send_keys("escape", [])
        Process.sleep(500)

        refute root_state().show_search_bar, "Escape should close the bar"
        {:ok, context}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Escape still closes the search bar (regression)
  # ---------------------------------------------------------------------------

  spex "Escape Still Closes Search Bar",
    description: "Pressing Escape continues to close the search bar after this change",
    tags: [:phase_13, :search_bar, :regression, :escape] do

    scenario "Escape closes the search bar as before" do
      given_ "the search bar is open", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)
        Probes.send_keys("f", [:ctrl])
        Process.sleep(400)
        {:ok, context}
      end

      when_ "we press Escape", context do
        Probes.send_keys("escape", [])
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the search bar should be closed" do
        Probes.send_text("R")
        Process.sleep(150)
        assert Query.text_visible?("R"),
          "'R' should appear in the editor — Escape should still close the search bar"
        :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 4. File picker — click-outside-to-cancel (regression; already implemented)
  # ---------------------------------------------------------------------------

  spex "File Picker Closes on Overlay Click",
    description: "Clicking the semi-transparent overlay outside the dialog cancels the file picker",
    tags: [:phase_13, :file_picker, :close_on_outside_click, :regression] do

    scenario "File picker modal cancels when clicking the overlay" do
      given_ "the file picker is open", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)

        # Open via File > Open
        Probes.click_element("icon_menu_file")
        Process.sleep(300)
        Probes.click_element("icon_menu_file_open")
        Process.sleep(600)

        # The file picker shows "Cancel" and "Open" buttons
        assert Query.text_visible?("Cancel"),
          "File picker should be open and show 'Cancel'"
        {:ok, context}
      end

      when_ "we click the overlay area (top-left corner, clearly outside the dialog)", context do
        # The modal dialog occupies the centre 70% of the viewport.
        # For an 800×600 window the dialog starts at roughly x=120, y=90.
        # Clicking at (20, 20) hits the semi-transparent overlay, not the dialog.
        Probes.click(20, 20)
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the file picker should be dismissed" do
        refute Query.text_visible?("Cancel"),
          "File picker should be closed — 'Cancel' button should no longer be visible"
        :ok
      end
    end
  end
end
