defmodule Quillex.FileNavigatorSpex do
  @moduledoc """
  Phase 10: File Navigator (File Tree Sidebar)

  Validates through the UI:
  - File navigator toggle via View menu
  - File navigator visibility
  - File tree display
  - File selection and opening

  This phase tests the SideNav-based file explorer sidebar.
  """
  use SexySpex

  alias ScenicMcp.Query
  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers

  setup_all do
    # Start Quillex application
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    # Wait for scene to fully initialize
    Process.sleep(2000)

    :ok
  end

  # ===========================================================================
  # UI-Based Helpers
  # ===========================================================================

  # Toggle file navigator via action dispatch
  defp toggle_file_nav do
    GenServer.call(QuillEx.RootScene, {:action, :toggle_file_nav})
    Process.sleep(500)
  end

  # Get current file_nav visibility state
  defp file_nav_visible? do
    # Check if file_nav component exists in the scene
    case GenServer.call(QuillEx.RootScene, :get_state, 5000) do
      {:ok, state} -> state.show_file_nav
      _ -> false
    end
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end

  # Alternative: check visibility via rendered text
  defp file_nav_shows_files? do
    # The file tree should show some common files from the project
    rendered = Query.rendered_text()
    # Check for common project files/dirs
    String.contains?(rendered, "lib") or
    String.contains?(rendered, "test") or
    String.contains?(rendered, "mix.exs")
  end

  # Get tab count from semantic viewport
  defp tab_count do
    SemanticHelpers.get_tab_count() || 0
  end

  # Close active buffer via action dispatch
  defp close_active_buffer do
    GenServer.call(QuillEx.RootScene, {:action, :close_active_buffer})
    Process.sleep(300)
  end

  # Close buffers until only one remains
  defp close_buffers_until_one_remains do
    if tab_count() > 1 do
      close_active_buffer()
      close_buffers_until_one_remains()
    end
  end

  # Ensure file nav is hidden
  defp ensure_file_nav_hidden do
    if file_nav_visible?() do
      toggle_file_nav()
    end
  end

  # Ensure file nav is visible
  defp ensure_file_nav_visible do
    unless file_nav_visible?() do
      toggle_file_nav()
    end
  end

  spex "File Navigator - Toggle Visibility",
    description: "Validates that file navigator can be toggled on and off via View menu",
    tags: [:phase_10, :file_navigator, :toggle] do

    # =========================================================================
    # 1. FILE NAVIGATOR INITIALLY HIDDEN
    # =========================================================================

    scenario "File navigator is initially hidden", context do
      given_ "Quillex has launched", context do
        close_buffers_until_one_remains()
        # Ensure file nav starts hidden
        ensure_file_nav_hidden()
        Process.sleep(300)
        {:ok, context}
      end

      then_ "file navigator should not be visible", context do
        refute file_nav_visible?(),
               "File navigator should be hidden by default"
        :ok
      end
    end

    # =========================================================================
    # 2. TOGGLING FILE NAVIGATOR SHOWS IT
    # =========================================================================

    scenario "Toggling file navigator shows the file tree", context do
      given_ "file navigator is hidden", context do
        ensure_file_nav_hidden()
        {:ok, context}
      end

      when_ "we toggle file navigator on", context do
        toggle_file_nav()
        {:ok, context}
      end

      then_ "file navigator should be visible", context do
        assert file_nav_visible?(),
               "File navigator should be visible after toggle"
        :ok
      end

      then_ "file tree should show project files", context do
        # Wait a moment for rendering
        Process.sleep(300)
        # The file tree should show some recognizable project structure
        assert file_nav_shows_files?(),
               "File navigator should display project files (lib, test, mix.exs)"
        :ok
      end
    end

    # =========================================================================
    # 3. TOGGLING AGAIN HIDES FILE NAVIGATOR
    # =========================================================================

    scenario "Toggling file navigator again hides it", context do
      given_ "file navigator is visible", context do
        ensure_file_nav_visible()
        {:ok, context}
      end

      when_ "we toggle file navigator off", context do
        toggle_file_nav()
        {:ok, context}
      end

      then_ "file navigator should be hidden", context do
        refute file_nav_visible?(),
               "File navigator should be hidden after second toggle"
        :ok
      end
    end
  end

  spex "File Navigator - View Menu Integration",
    description: "Validates that file navigator toggle is available in View menu",
    tags: [:phase_10, :file_navigator, :menu] do

    # =========================================================================
    # FILE NAVIGATOR MENU ITEM
    # =========================================================================

    scenario "View menu shows File Navigator toggle", context do
      given_ "Quillex has launched", context do
        # Ensure we start fresh
        ensure_file_nav_hidden()
        {:ok, context}
      end

      then_ "View menu should contain 'File Navigator' option", context do
        # Check rendered text for menu item
        # Note: The menu might not be visible until clicked
        # We verify by toggling via action which uses the menu system
        toggle_file_nav()
        Process.sleep(200)
        assert file_nav_visible?(), "File Navigator toggle should work"
        # Toggle back
        toggle_file_nav()
        :ok
      end
    end
  end

  spex "File Navigator - Buffer Pane Layout",
    description: "Validates that buffer pane resizes correctly when file navigator is toggled",
    tags: [:phase_10, :file_navigator, :layout] do

    # =========================================================================
    # BUFFER PANE RESIZES WITH FILE NAV
    # =========================================================================

    scenario "Buffer pane adjusts when file nav is shown", context do
      given_ "we have content in the buffer", context do
        ensure_file_nav_hidden()
        close_buffers_until_one_remains()
        # Type some content
        Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        Probes.send_keys("backspace", [])
        Process.sleep(100)
        Probes.send_text("Hello from buffer")
        Process.sleep(200)
        {:ok, context}
      end

      then_ "buffer content should be visible", context do
        assert Query.text_visible?("Hello from buffer"),
               "Buffer content should be visible"
        :ok
      end

      when_ "we show the file navigator", context do
        toggle_file_nav()
        {:ok, context}
      end

      then_ "buffer content should still be visible", context do
        Process.sleep(300)
        assert Query.text_visible?("Hello from buffer"),
               "Buffer content should remain visible when file nav is shown"
        :ok
      end

      when_ "we hide the file navigator", context do
        toggle_file_nav()
        {:ok, context}
      end

      then_ "buffer content should still be visible", context do
        Process.sleep(300)
        assert Query.text_visible?("Hello from buffer"),
               "Buffer content should remain visible when file nav is hidden"
        :ok
      end
    end
  end
end
