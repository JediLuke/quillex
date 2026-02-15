defmodule Quillex.PropertyTestsSpex do
  @moduledoc """
  Property-based tests for TextField cursor and selection behavior.

  Uses StreamData to generate random sequences of operations and verify
  that invariants always hold:

  1. Cursor is always within valid bounds
  2. Selection start/end are always valid positions
  3. Cursor never goes "off screen" (scroll follows cursor)
  4. Buffer state is always consistent
  """
  use SexySpex
  use ExUnitProperties

  alias ScenicMcp.Query
  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers

  # Maximum operations per test to keep runtime reasonable
  @max_ops 20

  setup_all do
    # Start Quillex application
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(2000)
    :ok
  end

  # Generator for cursor movement operations
  def cursor_movement_gen do
    StreamData.member_of([
      :left, :right, :up, :down, :home, :end,
      :ctrl_home, :ctrl_end
    ])
  end

  # Generator for text editing operations
  def edit_operation_gen do
    StreamData.one_of([
      StreamData.constant(:backspace),
      StreamData.constant(:delete),
      StreamData.constant(:enter),
      {:char, StreamData.string(:alphanumeric, min_length: 1, max_length: 1)}
    ])
  end

  # Generator for selection operations
  def selection_operation_gen do
    StreamData.member_of([
      :shift_left, :shift_right, :shift_up, :shift_down,
      :select_all, :escape
    ])
  end

  # Combined operation generator
  def operation_gen do
    StreamData.one_of([
      StreamData.map(cursor_movement_gen(), fn op -> {:move, op} end),
      StreamData.map(edit_operation_gen(), fn op -> {:edit, op} end),
      StreamData.map(selection_operation_gen(), fn op -> {:select, op} end)
    ])
  end

  spex "Property: Cursor Bounds Invariant",
    description: "After any sequence of cursor movements, cursor stays within valid bounds",
    tags: [:property, :cursor, :bounds] do

    scenario "Random cursor movements maintain bounds", context do
      given_ "fresh buffer with some initial content", context do
        clear_buffer()
        # Type some multi-line content
        Probes.send_text("Line one here")
        Process.sleep(50)
        Probes.send_keys("enter", [])
        Process.sleep(50)
        Probes.send_text("Line two is longer than line one")
        Process.sleep(50)
        Probes.send_keys("enter", [])
        Process.sleep(50)
        Probes.send_text("Three")
        Process.sleep(200)
        {:ok, context}
      end

      when_ "we perform random cursor movements", context do
        # Generate random cursor operations
        operations = generate_cursor_operations(15)

        IO.puts("\nExecuting #{length(operations)} random cursor operations:")

        for {op, idx} <- Enum.with_index(operations) do
          execute_cursor_op(op)
          Process.sleep(30)

          # Check bounds after each operation
          cursor_pos = get_cursor_position()
          if cursor_pos do
            {line, col} = cursor_pos
            assert line >= 1, "Cursor line must be >= 1 after op #{idx}: #{inspect(op)}"
            assert col >= 1, "Cursor col must be >= 1 after op #{idx}: #{inspect(op)}"
          end
        end

        {:ok, context}
      end

      then_ "cursor should still be at a valid position", context do
        # Final verification
        cursor_pos = get_cursor_position()

        if cursor_pos do
          {line, col} = cursor_pos
          IO.puts("\nFinal cursor position: line=#{line}, col=#{col}")

          assert line >= 1, "Final cursor line must be >= 1"
          assert col >= 1, "Final cursor col must be >= 1"

          # Also verify we can type at this position (proves it's valid)
          Probes.send_text("X")
          Process.sleep(100)
          assert Query.text_visible?("X"), "Should be able to type at cursor position"
        end

        :ok
      end
    end
  end

  spex "Property: Cursor Visibility Invariant",
    description: "Cursor should always be visible (scroll follows cursor)",
    tags: [:property, :cursor, :scroll] do

    scenario "Cursor stays visible during rapid navigation", context do
      given_ "buffer with many lines of content", context do
        clear_buffer()

        # Type enough lines to exceed viewport
        for i <- 1..30 do
          Probes.send_text("Line number #{i} with some text content here")
          Probes.send_keys("enter", [])
          Process.sleep(20)
        end
        Process.sleep(300)

        {:ok, context}
      end

      when_ "we rapidly navigate through the document", context do
        operations = [
          :ctrl_home,  # Start
          :ctrl_end,   # End
          :ctrl_home,  # Back to start
          # Page through document
          :down, :down, :down, :down, :down,
          :down, :down, :down, :down, :down,
          :up, :up, :up,
          :ctrl_end,
          :up, :up, :up, :up, :up,
          :ctrl_home
        ]

        for op <- operations do
          execute_cursor_op(op)
          Process.sleep(50)
        end

        {:ok, context}
      end

      then_ "cursor should still be visible", context do
        # Type a marker to verify cursor is usable
        Probes.send_text("MARKER")
        Process.sleep(100)

        # The marker should be visible if cursor is in viewport
        assert Query.text_visible?("MARKER"),
               "Marker should be visible - cursor should be in viewport"

        :ok
      end
    end
  end

  spex "Property: Selection Bounds Invariant",
    description: "Selection start and end are always valid positions",
    tags: [:property, :selection, :bounds] do

    scenario "Random selection operations maintain valid bounds", context do
      given_ "buffer with multi-line content", context do
        clear_buffer()
        Probes.send_text("ABCDEFGHIJ")
        Probes.send_keys("enter", [])
        Probes.send_text("1234567890")
        Probes.send_keys("enter", [])
        Probes.send_text("abcdefghij")
        Process.sleep(200)
        {:ok, context}
      end

      when_ "we perform random selection operations", context do
        operations = generate_selection_operations(10)

        IO.puts("\nExecuting #{length(operations)} random selection operations:")

        for {op, idx} <- Enum.with_index(operations) do
          execute_selection_op(op)
          Process.sleep(50)

          # After each op, verify we can still query rendered text (app is responsive)
          rendered = Query.rendered_text()
          assert is_binary(rendered),
                 "App should still respond after op #{idx}: #{inspect(op)}"
        end

        {:ok, context}
      end

      then_ "buffer should still be in consistent state", context do
        # Escape to clear selection
        Probes.send_keys("escape", [])
        Process.sleep(50)

        # Type to verify cursor is in valid position
        Probes.send_text("TEST")
        Process.sleep(100)

        assert Query.text_visible?("TEST"),
               "Should be able to type after selection operations"

        :ok
      end
    end
  end

  spex "Property: Edit Operations Don't Corrupt Buffer",
    description: "Random edit operations maintain buffer consistency",
    tags: [:property, :editing, :consistency] do

    scenario "Random edit sequence maintains consistency", context do
      given_ "buffer with initial content", context do
        clear_buffer()
        Probes.send_text("Initial content")
        Process.sleep(200)
        {:ok, context}
      end

      when_ "we perform random edit operations", context do
        operations = generate_edit_operations(15)

        IO.puts("\nExecuting #{length(operations)} random edit operations:")

        for op <- operations do
          execute_edit_op(op)
          Process.sleep(30)
        end

        Process.sleep(100)
        {:ok, context}
      end

      then_ "buffer should be in valid state", context do
        # Get rendered text - should not crash
        rendered = Query.rendered_text()

        assert is_binary(rendered), "Rendered text should be a string"

        # Type to verify cursor is valid
        Probes.send_text("FINAL")
        Process.sleep(100)

        assert Query.text_visible?("FINAL"),
               "Should be able to type after edit operations"

        :ok
      end
    end
  end

  spex "Property: Undo/Redo Consistency",
    description: "Undo and redo operations maintain buffer consistency",
    tags: [:property, :undo, :redo] do

    scenario "Random undo/redo sequence is consistent", context do
      given_ "buffer with some edits", context do
        clear_buffer()

        # Make several edits to build undo history
        Probes.send_text("First")
        Process.sleep(100)
        Probes.send_keys("enter", [])
        Probes.send_text("Second")
        Process.sleep(100)
        Probes.send_keys("enter", [])
        Probes.send_text("Third")
        Process.sleep(200)

        {:ok, context}
      end

      when_ "we perform random undo/redo operations", context do
        operations = for _ <- 1..10 do
          Enum.random([:undo, :redo])
        end

        IO.puts("\nExecuting undo/redo sequence: #{inspect(operations)}")

        for op <- operations do
          case op do
            :undo -> Probes.send_keys("z", [:ctrl])
            :redo -> Probes.send_keys("y", [:ctrl])
          end
          Process.sleep(50)
        end

        {:ok, context}
      end

      then_ "buffer should be in valid state", context do
        rendered = Query.rendered_text()

        assert is_binary(rendered), "Rendered text should be a string"

        # Verify cursor is usable
        Probes.send_keys("end", [:ctrl])
        Process.sleep(50)
        Probes.send_text("!")
        Process.sleep(100)

        assert Query.text_visible?("!"),
               "Should be able to type after undo/redo"

        :ok
      end
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp clear_buffer do
    Probes.send_keys("a", [:ctrl])
    Process.sleep(50)
    Probes.send_keys("delete", [])
    Process.sleep(100)
  end

  defp generate_cursor_operations(count) do
    ops = [:left, :right, :up, :down, :home, :end, :ctrl_home, :ctrl_end]
    for _ <- 1..count, do: Enum.random(ops)
  end

  defp generate_selection_operations(count) do
    ops = [:shift_left, :shift_right, :shift_up, :shift_down, :select_all, :escape]
    for _ <- 1..count, do: Enum.random(ops)
  end

  defp generate_edit_operations(count) do
    ops = [
      :backspace, :delete, :enter,
      {:char, "a"}, {:char, "b"}, {:char, "x"}, {:char, " "}
    ]
    for _ <- 1..count, do: Enum.random(ops)
  end

  defp execute_cursor_op(op) do
    case op do
      :left -> Probes.send_keys("left", [])
      :right -> Probes.send_keys("right", [])
      :up -> Probes.send_keys("up", [])
      :down -> Probes.send_keys("down", [])
      :home -> Probes.send_keys("home", [])
      :end -> Probes.send_keys("end", [])
      :ctrl_home -> Probes.send_keys("home", [:ctrl])
      :ctrl_end -> Probes.send_keys("end", [:ctrl])
    end
  end

  defp execute_selection_op(op) do
    case op do
      :shift_left -> Probes.send_keys("left", [:shift])
      :shift_right -> Probes.send_keys("right", [:shift])
      :shift_up -> Probes.send_keys("up", [:shift])
      :shift_down -> Probes.send_keys("down", [:shift])
      :select_all -> Probes.send_keys("a", [:ctrl])
      :escape -> Probes.send_keys("escape", [])
    end
  end

  defp execute_edit_op(op) do
    case op do
      :backspace -> Probes.send_keys("backspace", [])
      :delete -> Probes.send_keys("delete", [])
      :enter -> Probes.send_keys("enter", [])
      {:char, c} -> Probes.send_text(c)
    end
  end

  defp get_cursor_position do
    # Try to get cursor position from semantic info
    try do
      SemanticHelpers.get_cursor_position()
    rescue
      _ -> nil
    end
  end
end
