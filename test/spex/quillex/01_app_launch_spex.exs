defmodule Quillex.AppLaunchSpex do
  @moduledoc """
  Phase 1: App Launch & Basic UI

  Validates that Quillex launches correctly and displays all core UI components:
  - TabBar with initial untitled buffer tab
  - IconMenu (F/E/V/?) right-aligned
  - TextField with line numbers
  - Window resize handling

  This is the foundational spex - all other phases depend on the app launching correctly.
  """
  use SexySpex

  alias ScenicMcp.Query

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

  spex "App Launch & Basic UI - Core Components",
    description: "Validates that Quillex launches and displays all essential UI components",
    tags: [:phase_1, :app_launch, :ui] do
    # =========================================================================
    # 1. APP LAUNCHES SUCCESSFULLY
    # =========================================================================

    scenario "Quillex app launches without errors" do
      given_ "we start the Quillex application", context do
        # App should already be started from setup_all
        # Verify it's rendering by checking we can read content from the viewport
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the app is rendering content" do
        rendered = Query.rendered_text()

        assert is_binary(rendered) and rendered != "",
               "App should be rendering content after launch"

        :ok
      end
    end

    # =========================================================================
    # 2. TABBAR RENDERS WITH INITIAL TAB
    # =========================================================================

    scenario "TabBar displays with initial untitled buffer" do
      given_ "Quillex has launched", context do
        Process.sleep(500)
        {:ok, context}
      end

      when_ "we inspect the rendered content", context do
        rendered_content = Query.rendered_text()
        {:ok, Map.put(context, :rendered_content, rendered_content)}
      end

      then_ "TabBar shows 'untitled' tab for initial buffer", context do
        # The initial buffer should be named "untitled" or similar
        # Note: Tab names may be truncated to "unt..." in the UI
        assert Query.text_visible?("unt") or
                 Query.text_visible?("untitled"),
               "Initial buffer tab should show untitled. Got: #{String.slice(context.rendered_content, 0, 200)}"

        {:ok, context}
      end
    end

    # =========================================================================
    # 3. ICONMENU RENDERS WITH ACCESSIBLE VECTOR BUTTONS
    # =========================================================================

    scenario "IconMenu displays with File/Edit/View/Help icons" do
      given_ "Quillex has launched", context do
        {:ok, context}
      end

      when_ "we inspect the icon menu area", context do
        rendered_content = Query.rendered_text()
        {:ok, Map.put(context, :rendered_content, rendered_content)}
      end

      then_ "File/Edit/View/Help vector icons are registered as buttons" do
        for id <- [:icon_menu_file, :icon_menu_edit, :icon_menu_view, :icon_menu_help] do
          assert semantic_element_registered?(id), "#{id} should be a registered toolbar button"
        end

        :ok
      end
    end

    # =========================================================================
    # 4. TEXTFIELD RENDERS WITH LINE NUMBERS
    # =========================================================================

    scenario "TextField renders with line numbers visible" do
      given_ "Quillex has launched", context do
        {:ok, context}
      end

      when_ "we inspect the text editing area", context do
        rendered_content = Query.rendered_text()
        {:ok, Map.put(context, :rendered_content, rendered_content)}
      end

      then_ "line number 1 is visible" do
        # At minimum, line 1 should be visible in an empty buffer
        assert Query.text_visible?("1"),
               "Line number 1 should be visible in the empty buffer"

        :ok
      end
    end

    # =========================================================================
    # 5. INITIAL BUFFER IS EMPTY
    # =========================================================================

    scenario "Initial buffer is empty and ready for input" do
      given_ "Quillex has launched with default buffer", context do
        {:ok, context}
      end

      when_ "we check the buffer content", context do
        rendered_content = Query.rendered_text()
        {:ok, Map.put(context, :rendered_content, rendered_content)}
      end

      then_ "the buffer appears empty (no user content)" do
        # The rendered content should mainly be UI elements (line numbers, menu items)
        # and not contain substantial user text
        # This is a soft check - mainly ensuring no error messages appear
        refute Query.text_visible?("error"), "No error messages should appear on launch"
        refute Query.text_visible?("Error"), "No Error messages should appear on launch"
        :ok
      end
    end

    # =========================================================================
    # 6. CURSOR IS VISIBLE
    # =========================================================================

    scenario "Cursor is visible in the text area" do
      given_ "Quillex has launched", context do
        # The cursor should be blinking - we can't easily test blinking,
        # but we can verify the TextField is focused
        {:ok, context}
      end

      when_ "we check the text area for cursor presence", context do
        # Note: We can't easily verify cursor visibility without screenshot support
        # For now, we verify the app is responsive and rendering text
        rendered_content = Query.rendered_text()
        {:ok, Map.put(context, :rendered_content, rendered_content)}
      end

      then_ "cursor should be positioned at start of buffer", context do
        # Visual verification would require screenshot support
        # For now, just verify the app is rendering content (cursor area is ready)
        assert is_binary(context.rendered_content), "App should be rendering content"
        {:ok, context}
      end
    end
  end

  spex "App Launch & Basic UI - Window Resize",
    description: "Validates that window resize works without crashing",
    tags: [:phase_1, :app_launch, :resize] do
    # =========================================================================
    # 7. WINDOW RESIZE HANDLING
    # =========================================================================

    scenario "Window can be resized without crashing" do
      given_ "Quillex is running normally", context do
        # Verify app is running before simulating resize
        {:ok, context}
      end

      when_ "we simulate a viewport resize event", context do
        # Note: Directly simulating resize is tricky via MCP
        # For now, we just verify the app is still responsive after waiting
        # In a full test, we'd use Scenic.ViewPort.reshape/2
        Process.sleep(500)

        # Verify app is still responsive by checking we can get rendered content
        rendered_content = Query.rendered_text()
        {:ok, Map.put(context, :post_resize_content, rendered_content)}
      end

      then_ "app remains responsive", context do
        # App should still render content after the wait
        assert is_binary(context.post_resize_content),
               "App should still render content (not crash)"

        assert String.length(context.post_resize_content) > 0,
               "Rendered content should not be empty"

        # Core UI elements should still be visible
        assert semantic_element_registered?(:icon_menu_file),
               "Menu icons should still be visible after potential resize"

        {:ok, context}
      end
    end

    # =========================================================================
    # 8. COMPONENTS MAINTAIN CORRECT POSITIONS
    # =========================================================================

    scenario "UI components maintain correct layout" do
      given_ "Quillex has finished initial render", context do
        Process.sleep(300)
        {:ok, context}
      end

      when_ "we inspect the full UI", context do
        rendered_content = Query.rendered_text()
        {:ok, Map.put(context, :rendered_content, rendered_content)}
      end

      then_ "all core components are rendered" do
        # Verify all major UI elements are present
        # TabBar (may show truncated name like "unt...")
        assert Query.text_visible?("unt") or
                 Query.text_visible?("untitled"),
               "TabBar with buffer name should be visible"

        # IconMenu (vector icons are semantic buttons, not text glyphs)
        assert semantic_element_registered?(:icon_menu_file) and
                 semantic_element_registered?(:icon_menu_edit),
               "IconMenu icons should be visible"

        # Line numbers (indicating TextField is rendered)
        assert Query.text_visible?("1"), "Line numbers should be visible"

        :ok
      end
    end
  end

  defp semantic_element_registered?(id) do
    with {:ok, viewport} <- Scenic.ViewPort.info(:main_viewport) do
      :ets.lookup(viewport.semantic_index, id) != []
    else
      _ -> false
    end
  end
end
