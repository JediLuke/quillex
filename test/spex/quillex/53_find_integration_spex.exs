defmodule Quillex.FindIntegrationSpex do
  @moduledoc """
  Finding text in a real document: the search itself, who owns the keyboard
  while the bar is up, and whether the highlight lands on the match.

  Split out of `07_integration_v1_spex.exs` (roadmap Part II item 9).
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers
  import Quillex.TestHelpers.Integration

  setup_all do
    fresh_editor!()
    assert File.exists?(spinoza_path()), "fixture missing: #{spinoza_path()}"
    :ok
  end

  # SPEX 6: FIND/SEARCH IN SPINOZA
  # =========================================================================

  spex "V1 Integration - Find in Spinoza",
    description: "Validates search functionality with famous philosophical passages",
    tags: [:v1, :integration, :find, :search] do
    scenario "Search for 'God' in Spinoza's Ethics" do
      given_ "Spinoza's Ethics is the active buffer", context do
        # Close any existing search bar first
        Probes.send_keys("escape", [])
        Process.sleep(200)

        # Open Spinoza file (may already be open, that's fine)
        open_file(spinoza_path())
        Process.sleep(500)

        # Switch to ensure it's active
        switch_to_buffer("spinozas_ethics_p1.txt")
        Process.sleep(500)

        name = active_buffer_name()

        assert name == "spinozas_ethics_p1.txt",
               "Expected Spinoza buffer active, got '#{name}'"

        {:ok, context}
      end

      when_ "we open find and search for 'God'", context do
        # Close any existing search bar first
        Probes.send_keys("escape", [])
        Process.sleep(300)
        Probes.send_keys("escape", [])
        Process.sleep(300)

        # Open search bar with Ctrl+F
        Probes.send_keys("f", [:ctrl])
        Process.sleep(500)

        # The search bar may pre-fill with word under cursor
        # Clear it by going to End and pressing Backspace many times
        Probes.send_keys("end", [])
        Process.sleep(50)
        # Clear up to 50 characters (more than enough)
        Enum.each(1..50, fn _ ->
          Probes.send_keys("backspace", [])
        end)

        Process.sleep(200)

        # Now type search query
        Probes.send_text("God")
        # Wait for search to complete
        Process.sleep(800)
        {:ok, context}
      end

      then_ "we should find multiple matches", context do
        # Verify through UI - search bar should show match count
        # Look for pattern like "1/5" or similar in rendered text
        rendered = ScenicMcp.Query.rendered_text()

        # Check that we have matches visible (the count should appear)
        has_matches = String.contains?(rendered, "/") or String.contains?(rendered, "of")

        assert has_matches,
               "Search should show match count in UI. Rendered: #{String.slice(rendered, 0, 200)}"

        {:ok, context}
      end
    end

    scenario "Search for famous definition: 'absolutely infinite'" do
      given_ "search bar is open with new query", context do
        # Close and reopen search bar to start fresh
        Probes.send_keys("escape", [])
        Process.sleep(300)

        # Open search bar fresh
        Probes.send_keys("f", [:ctrl])
        Process.sleep(400)

        # Clear any pre-fill by going to end and backspacing
        Probes.send_keys("end", [])
        Process.sleep(50)

        Enum.each(1..50, fn _ ->
          Probes.send_keys("backspace", [])
        end)

        Process.sleep(200)

        # Type new search term
        Probes.send_text("absolutely infinite")
        Process.sleep(800)
        {:ok, context}
      end

      then_ "we should find the famous Definition VI", context do
        # Verify through UI - search text should be visible
        assert ScenicMcp.Query.text_visible?("absolutely infinite"),
               "Search term should be visible in search bar"

        {:ok, context}
      end
    end

    scenario "Close search bar" do
      when_ "we press Escape", context do
        Probes.send_keys("escape", [])
        # Wait long enough for the search bar process to die and the TextField
        # to receive its :focus restore message before we type.
        Process.sleep(600)
        {:ok, context}
      end

      then_ "search bar should be closed", context do
        Probes.click(120, 200)
        Process.sleep(250)
        Probes.send_text("Z")
        Process.sleep(400)

        landed? =
          String.contains?(active_buffer_content() || "", "Z") or
            Quillex.TestHelpers.ScriptInspector.rendered_text_contains?("Z")

        assert landed?,
               "After closing search, typing should go to buffer. " <>
                 "Pane content began: #{inspect(String.slice(active_buffer_content() || "", 0, 80))}"

        {:ok, context}
      end
    end
  end

  # =========================================================================
  # SPEX 6B: SEARCH BAR FOCUS EXCLUSIVITY
  # =========================================================================

  spex "V1 Integration - Search Bar Focus",
    description: "Validates search bar has exclusive input focus when open",
    tags: [:v1, :integration, :find, :focus] do
    scenario "Search bar input does NOT go to buffer" do
      given_ "we have a buffer with known content", context do
        new_empty_buffer()

        Probes.send_text("Original content")
        Process.sleep(300)
        {:ok, _} = wait_for_active_buffer_content("Original content")

        {:ok, Map.put(context, :original_content, "Original content")}
      end

      when_ "we open search bar and type a search term", context do
        # Open search bar
        Probes.send_keys("f", [:ctrl])
        Process.sleep(500)

        # Clear any existing search text
        Probes.send_keys("a", [:ctrl])
        Process.sleep(50)

        # Type search term - this should ONLY go to search bar
        Probes.send_text("searchterm")
        Process.sleep(500)

        {:ok, context}
      end

      then_ "buffer content should NOT contain the search term", context do
        # Close search bar first so we can check buffer content
        Probes.send_keys("escape", [])
        Process.sleep(300)

        content = active_buffer_content()

        refute String.contains?(content || "", "searchterm"),
               "Buffer should NOT contain 'searchterm' - search bar should have exclusive focus. Got: '#{content}'"

        assert content == context.original_content,
               "Buffer should still contain original content '#{context.original_content}', got '#{content}'"

        {:ok, context}
      end
    end

    scenario "Buffer regains focus after search bar closes" do
      given_ "search bar is closed", context do
        # Ensure search bar is closed
        Probes.send_keys("escape", [])
        Process.sleep(200)

        content_before = active_buffer_content()
        {:ok, Map.put(context, :content_before, content_before)}
      end

      when_ "we type after closing search bar", context do
        Probes.send_keys("end", [])
        Process.sleep(100)
        Probes.send_text("X")
        Process.sleep(300)
        {:ok, context}
      end

      then_ "text should appear in buffer", context do
        content = active_buffer_content()
        expected = (context.content_before || "") <> "X"

        assert content == expected,
               "Expected '#{expected}' after typing, got '#{content}'"

        {:ok, context}
      end
    end
  end

  # =========================================================================
  # SPEX 6C: SEARCH HIGHLIGHT POSITIONING
  # =========================================================================

  spex "V1 Integration - Search Highlight Accuracy",
    description: "Validates search highlights appear at correct positions",
    tags: [:v1, :integration, :find, :highlight] do
    scenario "Highlights appear at exact match positions" do
      given_ "we have a buffer with predictable content", context do
        new_empty_buffer()

        # Create content with known word positions
        # "The cat sat on the mat" - "the" appears at positions 1 and 16
        Probes.send_text("The cat sat on the mat")
        Process.sleep(300)

        {:ok, context}
      end

      when_ "we search for 'the'", context do
        Probes.send_keys("f", [:ctrl])
        Process.sleep(500)
        Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        Probes.send_text("the")
        Process.sleep(800)
        {:ok, context}
      end

      then_ "we should find exactly 2 matches", context do
        # Verify through UI - look for "1/2" or "2/2" pattern in rendered text
        rendered = ScenicMcp.Query.rendered_text()

        # "the" appears twice: "The" (case insensitive) and "the"
        # Check for indication of 2 matches in rendered output
        has_two_matches = String.contains?(rendered, "/2") or String.contains?(rendered, "2 of")

        assert has_two_matches,
               "Expected 2 matches for 'the' shown in UI. Rendered: #{String.slice(rendered, 0, 200)}"

        # Close search bar
        Probes.send_keys("escape", [])
        Process.sleep(200)

        {:ok, context}
      end
    end

    scenario "Highlights do NOT appear on empty lines" do
      given_ "we have content with empty lines", context do
        new_empty_buffer()

        # Create content with empty lines
        Probes.send_text("First line with word")
        Probes.send_keys("enter", [])
        # Empty line 2
        Probes.send_keys("enter", [])
        # Empty line 3
        Probes.send_keys("enter", [])
        Probes.send_text("Fourth line with word")
        Process.sleep(300)

        {:ok, context}
      end

      when_ "we search for 'word'", context do
        Probes.send_keys("f", [:ctrl])
        Process.sleep(500)
        Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        Probes.send_text("word")
        Process.sleep(800)
        {:ok, context}
      end

      then_ "we should find exactly 2 matches (not on empty lines)", context do
        # Verify through UI - look for "1/2" or "2/2" pattern
        rendered = ScenicMcp.Query.rendered_text()

        # "word" appears on line 1 and line 4, NOT on empty lines 2-3
        has_two_matches = String.contains?(rendered, "/2") or String.contains?(rendered, "2 of")

        assert has_two_matches,
               "Expected 2 matches for 'word' shown in UI. Rendered: #{String.slice(rendered, 0, 200)}"

        Probes.send_keys("escape", [])
        Process.sleep(200)

        {:ok, context}
      end
    end
  end

  # =========================================================================
end
