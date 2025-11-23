defmodule Quillex.TestHelpers.SemanticHelpers do
  @moduledoc """
  Helper functions for working with the semantic layer in tests.
  
  These helpers search across all graphs to find semantic elements,
  not just the root graph.
  """
  
  alias Scenic.Semantic.Query
  
  @doc """
  Find elements by type across ALL graphs in the viewport.
  
  This is more robust than Query.find_by_type which only searches one graph.
  """
  def find_by_type_all_graphs(viewport, type) do
    # Get all semantic data
    semantic_data = :ets.tab2list(viewport.semantic_table)
    
    elements = Enum.flat_map(semantic_data, fn {_graph_key, info} ->
      ids = get_in(info, [:by_type, type]) || []
      Enum.map(ids, &Map.get(info.elements, &1))
    end)
    
    {:ok, elements}
  end
  
  @doc """
  Find the first text buffer across all graphs.
  """
  def find_text_buffer(viewport) do
    case find_by_type_all_graphs(viewport, :text_buffer) do
      {:ok, [buffer | _]} -> {:ok, buffer}
      {:ok, []} -> {:error, :no_text_buffer}
      error -> error
    end
  end
  
  @doc """
  Get text content from any text buffer in the viewport.
  """
  def get_buffer_text(viewport) do
    case find_text_buffer(viewport) do
      {:ok, buffer} -> {:ok, buffer.content || ""}
      error -> error
    end
  end
  
  @doc """
  Wait for buffer content to match expected text.
  """
  def wait_for_buffer_content(viewport, expected_text, timeout \\ 5000) do
    end_time = System.monotonic_time(:millisecond) + timeout
    
    wait_for_content_loop(viewport, expected_text, end_time)
  end
  
  defp wait_for_content_loop(viewport, expected_text, end_time) do
    case find_text_buffer(viewport) do
      {:ok, buffer} ->
        if buffer.content == expected_text do
          {:ok, buffer}
        else
          if System.monotonic_time(:millisecond) < end_time do
            Process.sleep(50)
            # Get fresh viewport info
            case Scenic.ViewPort.info(:main_viewport) do
              {:ok, fresh_viewport} ->
                wait_for_content_loop(fresh_viewport, expected_text, end_time)
              _ ->
                {:error, :viewport_not_found}
            end
          else
            {:error, {:timeout, "Expected: '#{expected_text}', Got: '#{buffer.content}'"}}
          end
        end
        
      error ->
        if System.monotonic_time(:millisecond) < end_time do
          Process.sleep(50)
          # Get fresh viewport info
          case Scenic.ViewPort.info(:main_viewport) do
            {:ok, fresh_viewport} ->
              wait_for_content_loop(fresh_viewport, expected_text, end_time)
            _ ->
              {:error, :viewport_not_found}
          end
        else
          error
        end
    end
  end
  
  @doc """
  Find elements with a specific semantic role across all graphs.
  """
  def find_by_role(viewport, role) do
    # Get all semantic data
    semantic_data = :ets.tab2list(viewport.semantic_table)
    
    elements = Enum.flat_map(semantic_data, fn {_graph_key, info} ->
      info.elements
      |> Map.values()
      |> Enum.filter(fn elem -> 
        get_in(elem, [:semantic, :role]) == role
      end)
    end)
    
    {:ok, elements}
  end
  
  @doc """
  Debug function to show all semantic elements in the viewport.
  """
  def dump_semantic_elements(viewport) do
    semantic_data = :ets.tab2list(viewport.semantic_table)
    
    IO.puts("\n=== ALL SEMANTIC ELEMENTS ===")
    for {graph_key, info} <- semantic_data do
      if map_size(info.elements) > 0 do
        IO.puts("\nGraph: #{inspect(graph_key)}")
        for {id, elem} <- info.elements do
          if elem.semantic && map_size(elem.semantic) > 0 do
            IO.puts("  Element #{id}: #{inspect(elem.semantic)}")
          end
        end
      end
    end
    
    :ok
  end
end