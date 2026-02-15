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
      case info do
        %{by_type: by_type, elements: elements} ->
          ids = Map.get(by_type, type, [])
          Enum.map(ids, &Map.get(elements, &1))

        %{elements: elements} ->
          elements
          |> Map.values()
          |> Enum.filter(fn elem ->
            Map.get(elem.semantic || %{}, :type) == type
          end)

        _ ->
          []
      end
    end)
    
    {:ok, elements}
  end
  
  @doc """
  Find the first text buffer across all graphs.
  """
  def find_text_buffer(viewport) do
    case find_latest_by_type(viewport, :text_buffer, fn _ -> true end) do
      {:ok, buffer} ->
        {:ok, buffer}

      _ ->
        case find_buffer_text_field(viewport) do
          {:ok, buffer} ->
            {:ok, buffer}

          _ ->
            find_by_id_all_graphs(viewport, :semantic_buffer_content)
        end
    end
  end

  def find_text_buffer(viewport, buffer_id) when not is_nil(buffer_id) do
    case find_latest_by_type(viewport, :text_buffer, fn elem ->
           semantic = elem.semantic || %{}
           semantic[:buffer_id] == buffer_id
         end) do
      {:ok, buffer} -> {:ok, buffer}
      _ -> find_text_buffer(viewport)
    end
  end

  def find_buffer_selection(viewport) do
    find_latest_by_type(viewport, :text_buffer, fn elem ->
      semantic = elem.semantic || %{}
      semantic[:field_id] == :buffer_pane or elem.id == :semantic_buffer_content
    end)
  end

  def find_buffer_selection(viewport, buffer_id) when not is_nil(buffer_id) do
    case find_latest_by_type(viewport, :text_buffer, fn elem ->
           semantic = elem.semantic || %{}
           semantic[:buffer_id] == buffer_id
         end) do
      {:ok, buffer} -> {:ok, buffer}
      _ -> find_buffer_selection(viewport)
    end
  end

  defp find_by_id_all_graphs(viewport, id) do
    semantic_data = :ets.tab2list(viewport.semantic_table)

    elements =
      Enum.flat_map(semantic_data, fn {_graph_key, info} ->
        case info do
          %{elements: elements} ->
            case Map.get(elements, id) do
              nil -> []
              elem -> [elem]
            end

          _ ->
            []
        end
      end)

    case elements do
      [elem | _] -> {:ok, elem}
      _ -> {:error, :not_found}
    end
  end

  defp find_latest_by_type(viewport, type, filter_fn) do
    semantic_data = :ets.tab2list(viewport.semantic_table)

    latest =
      semantic_data
      |> Enum.flat_map(fn {_graph_key, info} ->
        timestamp = Map.get(info, :timestamp, 0)

        elements =
          case info do
            %{by_type: by_type, elements: elements} ->
              ids = Map.get(by_type, type, [])
              Enum.map(ids, &Map.get(elements, &1))

            %{elements: elements} ->
              elements
              |> Map.values()
              |> Enum.filter(fn elem ->
                Map.get(elem.semantic || %{}, :type) == type
              end)

            _ ->
              []
          end

        elements
        |> Enum.filter(filter_fn)
        |> Enum.map(&{timestamp, &1})
      end)
      |> Enum.max_by(fn {timestamp, _elem} -> timestamp end, fn -> nil end)

    case latest do
      nil -> {:error, :not_found}
      {_timestamp, elem} -> {:ok, elem}
    end
  end

  defp find_buffer_text_field(viewport) do
    case find_by_type_all_graphs(viewport, :text_field) do
      {:ok, elements} ->
        case Enum.find(elements, fn elem ->
               Map.get(elem.semantic || %{}, :field_id) == :buffer_pane
             end) do
          nil -> {:error, :no_text_buffer}
          buffer -> {:ok, buffer}
        end

      error ->
        error
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

    wait_for_content_loop(viewport, expected_text, end_time, nil)
  end

  def wait_for_buffer_content(viewport, expected_text, buffer_id, timeout) do
    end_time = System.monotonic_time(:millisecond) + timeout

    wait_for_content_loop(viewport, expected_text, end_time, buffer_id)
  end
  
  defp wait_for_content_loop(viewport, expected_text, end_time, buffer_id) do
    buffer_lookup =
      if buffer_id do
        find_text_buffer(viewport, buffer_id)
      else
        find_text_buffer(viewport)
      end

    case buffer_lookup do
      {:ok, buffer} ->
        if buffer.content == expected_text do
          {:ok, buffer}
        else
          if System.monotonic_time(:millisecond) < end_time do
            Process.sleep(50)
            # Get fresh viewport info
            case Scenic.ViewPort.info(:main_viewport) do
              {:ok, fresh_viewport} ->
                wait_for_content_loop(fresh_viewport, expected_text, end_time, buffer_id)
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
              wait_for_content_loop(fresh_viewport, expected_text, end_time, buffer_id)
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
      case info do
        %{elements: elements} ->
          elements
          |> Map.values()
          |> Enum.filter(fn elem ->
            Map.get(elem.semantic || %{}, :role) == role
          end)
        _ ->
          []
      end
    end)
    
    {:ok, elements}
  end
  
  @doc """
  Get the current cursor position from the buffer's semantic data.
  Returns {line, column} or nil if not found.
  """
  def get_cursor_position do
    case Scenic.ViewPort.info(:main_viewport) do
      {:ok, viewport} ->
        get_cursor_position(viewport)
      _ ->
        nil
    end
  end

  def get_cursor_position(viewport) do
    case find_text_buffer(viewport) do
      {:ok, buffer} ->
        semantic = buffer.semantic || %{}
        case semantic[:cursor] do
          {line, col} -> {line, col}
          _ -> nil
        end
      _ ->
        nil
    end
  end

  @doc """
  Get the current selection from the buffer's semantic data.
  Returns {start_pos, end_pos} or nil if no selection.
  """
  def get_selection do
    case Scenic.ViewPort.info(:main_viewport) do
      {:ok, viewport} ->
        get_selection(viewport)
      _ ->
        nil
    end
  end

  def get_selection(viewport) do
    case find_text_buffer(viewport) do
      {:ok, buffer} ->
        semantic = buffer.semantic || %{}
        semantic[:selection]
      _ ->
        nil
    end
  end

  @doc """
  Debug function to show all semantic elements in the viewport.
  """
  def dump_semantic_elements(viewport) do
    semantic_data = :ets.tab2list(viewport.semantic_table)

    IO.puts("\n=== ALL SEMANTIC ELEMENTS ===")
    for {graph_key, info} <- semantic_data do
      if match?(%{elements: elements} when map_size(elements) > 0, info) do
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

  # ===========================================================================
  # Scroll Semantic Queries
  # ===========================================================================

  @doc """
  Get scroll offset from the active text buffer.
  Returns {offset_x, offset_y} or {0, 0} if not found.
  """
  def get_scroll_offset do
    with_viewport(fn viewport -> get_scroll_offset(viewport) end) || {0, 0}
  end

  def get_scroll_offset(viewport) do
    case find_text_buffer(viewport) do
      {:ok, buffer} ->
        scroll = get_in(buffer, [:semantic, :scroll]) || %{}
        {scroll[:offset_x] || 0, scroll[:offset_y] || 0}
      _ ->
        {0, 0}
    end
  end

  @doc """
  Get full scroll info from the active text buffer.
  Returns map with offset_x, offset_y, viewport_width/height, content_width/height
  or nil if not found.
  """
  def get_scroll_info do
    with_viewport(fn viewport -> get_scroll_info(viewport) end)
  end

  def get_scroll_info(viewport) do
    case find_text_buffer(viewport) do
      {:ok, buffer} ->
        get_in(buffer, [:semantic, :scroll])
      _ ->
        nil
    end
  end

  @doc """
  Wait for scroll offset to change from initial value.
  Returns {:ok, new_offset} or {:error, :timeout}
  """
  def wait_for_scroll_change(initial_offset, timeout \\ 3000) do
    end_time = System.monotonic_time(:millisecond) + timeout
    wait_for_scroll_change_loop(initial_offset, end_time)
  end

  defp wait_for_scroll_change_loop(initial_offset, end_time) do
    current = get_scroll_offset()

    if current != initial_offset do
      {:ok, current}
    else
      if System.monotonic_time(:millisecond) < end_time do
        Process.sleep(50)
        wait_for_scroll_change_loop(initial_offset, end_time)
      else
        {:error, {:timeout, "Scroll offset unchanged from #{inspect(initial_offset)}"}}
      end
    end
  end

  # ===========================================================================
  # TabBar Semantic Queries
  # ===========================================================================

  @doc """
  Find the tab bar semantic element in the viewport.
  Returns {:ok, tab_bar_info} or {:error, :not_found}
  """
  def find_tab_bar do
    with_viewport(fn viewport -> find_tab_bar(viewport) end)
  end

  def find_tab_bar(viewport) do
    find_latest_by_type(viewport, :tab_bar, fn _ -> true end)
  end

  @doc """
  Get the number of tabs currently visible in the tab bar.
  Returns integer or nil if tab bar not found.
  """
  def get_tab_count do
    with_viewport(fn viewport -> get_tab_count(viewport) end)
  end

  def get_tab_count(viewport) do
    case find_tab_bar(viewport) do
      {:ok, tab_bar} ->
        semantic = tab_bar.semantic || %{}
        semantic[:tab_count] || 0
      _ ->
        nil
    end
  end

  @doc """
  Get the list of tab labels currently in the tab bar.
  Returns list of strings or empty list if not found.
  """
  def get_tab_labels do
    with_viewport(fn viewport -> get_tab_labels(viewport) end)
  end

  def get_tab_labels(viewport) do
    case find_tab_bar(viewport) do
      {:ok, tab_bar} ->
        semantic = tab_bar.semantic || %{}
        tabs = semantic[:tabs] || []
        Enum.map(tabs, & &1[:label])
      _ ->
        []
    end
  end

  @doc """
  Get the currently selected tab's ID.
  Returns tab_id or nil if not found.
  """
  def get_selected_tab_id do
    with_viewport(fn viewport -> get_selected_tab_id(viewport) end)
  end

  def get_selected_tab_id(viewport) do
    case find_tab_bar(viewport) do
      {:ok, tab_bar} ->
        semantic = tab_bar.semantic || %{}
        semantic[:selected_id]
      _ ->
        nil
    end
  end

  @doc """
  Get the currently selected tab's label.
  Returns label string or nil if not found.
  """
  def get_selected_tab_label do
    with_viewport(fn viewport -> get_selected_tab_label(viewport) end)
  end

  def get_selected_tab_label(viewport) do
    case find_tab_bar(viewport) do
      {:ok, tab_bar} ->
        semantic = tab_bar.semantic || %{}
        tabs = semantic[:tabs] || []
        selected_id = semantic[:selected_id]

        case Enum.find(tabs, & &1[:id] == selected_id) do
          nil -> nil
          tab -> tab[:label]
        end
      _ ->
        nil
    end
  end

  @doc """
  Check if a tab with the given label exists in the tab bar.
  Returns boolean.
  """
  def tab_exists?(label) when is_binary(label) do
    label in get_tab_labels()
  end

  @doc """
  Check if a tab with the given label is currently selected.
  Returns boolean.
  """
  def tab_selected?(label) when is_binary(label) do
    get_selected_tab_label() == label
  end

  @doc """
  Wait for the tab count to reach expected value.
  Returns {:ok, count} or {:error, :timeout}
  """
  def wait_for_tab_count(expected_count, timeout \\ 3000) do
    end_time = System.monotonic_time(:millisecond) + timeout
    wait_for_tab_count_loop(expected_count, end_time)
  end

  defp wait_for_tab_count_loop(expected_count, end_time) do
    current = get_tab_count()

    if current == expected_count do
      {:ok, current}
    else
      if System.monotonic_time(:millisecond) < end_time do
        Process.sleep(50)
        wait_for_tab_count_loop(expected_count, end_time)
      else
        {:error, {:timeout, "Expected #{expected_count} tabs, got #{current}"}}
      end
    end
  end

  @doc """
  Wait for a tab with the given label to appear.
  Returns {:ok, label} or {:error, :timeout}
  """
  def wait_for_tab(label, timeout \\ 3000) do
    end_time = System.monotonic_time(:millisecond) + timeout
    wait_for_tab_loop(label, end_time)
  end

  defp wait_for_tab_loop(label, end_time) do
    if tab_exists?(label) do
      {:ok, label}
    else
      if System.monotonic_time(:millisecond) < end_time do
        Process.sleep(50)
        wait_for_tab_loop(label, end_time)
      else
        {:error, {:timeout, "Tab '#{label}' not found. Available: #{inspect(get_tab_labels())}"}}
      end
    end
  end

  @doc """
  Wait for the specified tab to become selected.
  Returns {:ok, label} or {:error, :timeout}
  """
  def wait_for_tab_selected(label, timeout \\ 3000) do
    end_time = System.monotonic_time(:millisecond) + timeout
    wait_for_tab_selected_loop(label, end_time)
  end

  defp wait_for_tab_selected_loop(label, end_time) do
    if tab_selected?(label) do
      {:ok, label}
    else
      if System.monotonic_time(:millisecond) < end_time do
        Process.sleep(50)
        wait_for_tab_selected_loop(label, end_time)
      else
        current = get_selected_tab_label()
        {:error, {:timeout, "Expected '#{label}' selected, got '#{current}'"}}
      end
    end
  end

  # ===========================================================================
  # Viewport Helpers
  # ===========================================================================

  @doc """
  Execute a function with the current viewport.
  Handles viewport lookup and returns nil on failure.
  """
  def with_viewport(fun) when is_function(fun, 1) do
    case Scenic.ViewPort.info(:main_viewport) do
      {:ok, viewport} -> fun.(viewport)
      _ -> nil
    end
  end

  @doc """
  Get fresh viewport info.
  """
  def get_viewport do
    case Scenic.ViewPort.info(:main_viewport) do
      {:ok, viewport} -> {:ok, viewport}
      error -> error
    end
  end
end
