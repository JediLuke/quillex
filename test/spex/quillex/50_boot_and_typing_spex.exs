defmodule Quillex.BootAndTypingSpex do
  @moduledoc """
  Booting, and typing into an empty buffer.

  Split out of `07_integration_v1_spex.exs` (roadmap Part II item 9). The
  original held every integration scenario in one file whose scenarios
  inherited each other's buffers, so it failed a different, shifting set of
  them on identical code. Each file now starts from a known editor and says so.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers
  import Quillex.TestHelpers.Integration

  setup_all do
    fresh_editor!()
    :ok
  end

  # SPEX 1: BOOT & INITIAL STATE
  # =========================================================================

  spex "V1 Integration - Boot State",
    description: "Validates app can create empty untitled buffers",
    tags: [:v1, :integration, :boot] do
    scenario "Creating a new buffer results in untitled buffer" do
      given_ "Quillex has launched", context do
        Process.sleep(500)
        {:ok, context}
      end

      when_ "we create a new buffer", context do
        trigger_action(:new_buffer)
        Process.sleep(500)
        names = buffer_names()
        count = buffer_count()
        {:ok, Map.merge(context, %{names: names, count: count})}
      end

      then_ "there should be at least one buffer with 'untitled' in name", context do
        assert context.count >= 1, "Expected at least 1 buffer, got #{context.count}"
        has_untitled = Enum.any?(context.names, &String.contains?(&1, "untitled"))
        assert has_untitled, "Expected 'untitled' buffer, got #{inspect(context.names)}"
        {:ok, context}
      end
    end
  end

  # =========================================================================
  # SPEX 2: BASIC TYPING (Double Character Bug Check)
  # =========================================================================

  spex "V1 Integration - Basic Typing",
    description: "Validates typing produces correct output (no double characters)",
    tags: [:v1, :integration, :typing] do
    scenario "Typing produces exactly the typed characters" do
      given_ "we have an empty buffer", context do
        new_empty_buffer()

        {:ok, context}
      end

      when_ "we type 'Hello World'", context do
        Probes.send_text("Hello World")
        Process.sleep(500)
        {:ok, context}
      end

      then_ "buffer should contain exactly 'Hello World'", context do
        {:ok, _} = wait_for_active_buffer_content("Hello World")
        content = active_buffer_content()

        assert content == "Hello World",
               "Expected 'Hello World', got '#{content}' (length: #{String.length(content || "")})"

        {:ok, context}
      end
    end

    scenario "Each character appears exactly once" do
      given_ "we have an empty buffer", context do
        new_empty_buffer()
        {:ok, context}
      end

      when_ "we type 'abc'", context do
        Probes.send_text("abc")
        Process.sleep(500)
        {:ok, context}
      end

      then_ "buffer should contain exactly 'abc' (3 characters)", context do
        {:ok, _} = wait_for_active_buffer_content("abc")
        content = active_buffer_content()

        assert content == "abc",
               "Expected 'abc' (3 chars), got '#{content}' (#{String.length(content || "")} chars)"

        {:ok, context}
      end
    end
  end

  # =========================================================================
end
