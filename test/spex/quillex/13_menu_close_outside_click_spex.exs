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

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    # Wait for the scene to fully initialise
    Process.sleep(2000)
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

  spex "Search Bar Closes on Outside Click",
    description: "Clicking below the search bar in the editor area closes it",
    tags: [:phase_13, :search_bar, :close_on_outside_click] do

    scenario "Search bar is dismissed when the user clicks in the buffer area" do
      given_ "the search bar is open", context do
        # Clean slate — escape closes any open menu/picker, then click the
        # editor area to guarantee focus is on the buffer pane before typing.
        Probes.send_keys("escape", [])
        Process.sleep(200)
        Probes.click(400, 200)
        Process.sleep(100)
        Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        Probes.send_keys("backspace", [])
        Process.sleep(50)
        Probes.send_text("outside click test content")
        Process.sleep(100)

        # Click editor area again to ensure buffer pane focus before Ctrl+F,
        # so the key event reaches the TextField (which sends {:find_requested}).
        Probes.click(400, 200)
        Process.sleep(100)

        # Open the search bar
        Probes.send_keys("f", [:ctrl])
        Process.sleep(500)

        # Verify the search bar is open
        visible = Query.text_visible?("<") or Query.text_visible?(">") or
                  Query.text_visible?("0/0") or Query.text_visible?("Search...")
        assert visible, "Search bar should be visible"
        {:ok, context}
      end

      when_ "we click in the buffer area below the search bar", context do
        # Top bar = 35 px, search bar = 36 px, so the buffer area starts at y > 71.
        # Click well inside the buffer area.
        Probes.click(400, 200)
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the search bar should be closed and keystrokes go to the editor" do
        # If the search bar is closed, the buffer pane regains focus and
        # typing should insert text into the buffer, not the search field.
        Probes.send_text("Q")
        Process.sleep(200)
        assert Query.text_visible?("Q"),
          "'Q' should appear in the editor — search bar should be closed"
        :ok
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
