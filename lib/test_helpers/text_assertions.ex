defmodule Quillex.TestHelpers.TextAssertions do
  @moduledoc """
  Helper assertions for text content in tests.
  """
  
  alias Quillex.TestHelpers.ScriptInspector
  
  @doc """
  Assert that the rendered text contains the expected content.
  Handles multi-line text properly.
  """
  def assert_text_contains(expected, opts \\ []) do
    # Use extract_user_content to filter out line numbers and GUI elements
    rendered_lines = ScriptInspector.extract_user_content()
    rendered_text = Enum.join(rendered_lines, opts[:join_with] || "\n")
    
    unless String.contains?(rendered_text, expected) do
      raise ExUnit.AssertionError,
        message: """
        Expected text to contain: #{inspect(expected)}
        
        Actual rendered text:
        #{rendered_text}
        
        Lines found:
        #{rendered_lines |> Enum.with_index() |> Enum.map(fn {line, idx} -> "  #{idx}: '#{line}'" end) |> Enum.join("\n")}
        """
    end
    
    true
  end
  
  @doc """
  Assert exact text match.
  """
  def assert_text_equals(expected, opts \\ []) do
    rendered_lines = ScriptInspector.extract_user_content()
    rendered_text = Enum.join(rendered_lines, opts[:join_with] || "\n")
    
    unless rendered_text == expected do
      raise ExUnit.AssertionError,
        message: """
        Expected text: #{inspect(expected)}
        Actual text:   #{inspect(rendered_text)}
        """
    end
    
    true
  end
  
  @doc """
  Get the current rendered text as a string.
  """
  def get_rendered_text do
    ScriptInspector.extract_user_content()
    |> Enum.join("\n")
  end
end