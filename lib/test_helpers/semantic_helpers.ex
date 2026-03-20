defmodule Quillex.TestHelpers.SemanticHelpers do
  @moduledoc """
  Helper functions for working with the semantic layer in tests.

  These helpers search across all graphs to find semantic elements,
  not just the root graph.
  """

  alias ScenicMcp.Tools
  alias ScenicMcp.Probes

  @doc """
  Find elements by type across ALL graphs in the viewport.

  Handles both ETS formats:
  - Format 1 (build_semantic_info): `{graph_key, %{elements: %{id => elem}}}`
  - Format 2 (manual registration): `{{scene_name, id}, %Scenic.Semantic.Compiler.Entry{}}`
  """
  def find_by_type_all_graphs(viewport, type) do
    semantic_data = :ets.tab2list(viewport.semantic_table)

    elements = Enum.flat_map(semantic_data, fn
      # Format 2: {{scene_name, entry_id}, %Entry{}}
      {{_scene_name, _entry_id}, %Scenic.Semantic.Compiler.Entry{type: entry_type} = entry} when entry_type == type ->
        [entry_to_element(entry)]

      # Format 1: {graph_key, %{elements: %{id => elem}}}
      {_graph_key, %{elements: elements}} ->
        elements
        |> Map.values()
        |> Enum.filter(fn elem ->
          Map.get(Map.get(elem, :semantic, %{}) || %{}, :type) == type
        end)

      _ ->
        []
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
      Enum.flat_map(semantic_data, fn
        # Format 2
        {{_scene_name, entry_id}, %Scenic.Semantic.Compiler.Entry{} = entry} when entry_id == id ->
          [entry_to_element(entry)]

        # Format 1
        {_graph_key, %{elements: elements}} ->
          case Map.get(elements, id) do
            nil -> []
            elem -> [elem]
          end

        _ ->
          []
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
      |> Enum.flat_map(fn
        # Format 2: {{scene_name, entry_id}, %Entry{}}
        {{_scene_name, _entry_id}, %Scenic.Semantic.Compiler.Entry{type: entry_type} = entry} when entry_type == type ->
          elem = entry_to_element(entry)
          if filter_fn.(elem), do: [{0, elem}], else: []

        # Format 1: {graph_key, %{elements: ...}}
        {_graph_key, %{elements: elements} = info} ->
          timestamp = Map.get(info, :timestamp, 0)

          elements
          |> Map.values()
          |> Enum.filter(fn elem ->
            Map.get(Map.get(elem, :semantic, %{}) || %{}, :type) == type
          end)
          |> Enum.filter(filter_fn)
          |> Enum.map(&{timestamp, &1})

        _ ->
          []
      end)
      |> Enum.max_by(fn {timestamp, _elem} -> timestamp end, fn -> nil end)

    case latest do
      nil -> {:error, :not_found}
      {_timestamp, elem} -> {:ok, elem}
    end
  end

  # Convert a Format 2 (manually registered) Scenic.Semantic.Compiler.Entry
  # into the Format 1 (graph-based) element map shape that callers expect.
  # Format 1 elements are maps with :id, :type, :content, :semantic, etc.
  #
  # When entry.value is a map, it is treated as custom semantic metadata from
  # the component's semantic_metadata/1 callback (buffer_id, cursor_position,
  # selection, scroll, etc.) and merged into the :semantic output map.
  # Standard fields (type, label, role, value, clickable) take priority on conflict.
  defp entry_to_element(%Scenic.Semantic.Compiler.Entry{} = entry) do
    base_semantic = %{
      type: entry.type,
      label: entry.label,
      role: entry.role,
      value: entry.value,
      clickable: entry.clickable
    }

    # Merge custom metadata when value is a map so that fields like buffer_id,
    # cursor_position, selection, and scroll are accessible directly via
    # semantic.field_name instead of semantic.value.field_name.
    # base_semantic takes priority to preserve the standard fields.
    full_semantic =
      case entry.value do
        %{} = meta when is_map(meta) -> Map.merge(meta, base_semantic)
        _ -> base_semantic
      end

    %{
      id: entry.id,
      type: entry.type,
      content: entry.label || "",
      semantic: full_semantic,
      clickable: entry.clickable,
      label: entry.label || "",
      screen_bounds: entry.screen_bounds,
      local_bounds: entry.local_bounds
    }
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
        case semantic[:cursor_position] do
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

  Reads the aggregate entry written by ScenicWidgets.TabBar.register_semantic_elements/2.
  That function stores a plain map (not a %Scenic.Semantic.Compiler.Entry{}) under the
  key {scene_name, :tab_bar_aggregate} so that rich metadata (tab_count, tabs with labels,
  selected_id) survives — the Entry struct has no fields for custom data.
  """
  def find_tab_bar do
    with_viewport(fn viewport -> find_tab_bar(viewport) end)
  end

  def find_tab_bar(viewport) do
    case find_tab_bar_aggregate(viewport) do
      {:ok, _} = result ->
        result

      _ ->
        case find_latest_by_type(viewport, :tab_bar, fn _ -> true end) do
          {:ok, _} = result -> result
          _ -> build_tab_bar_from_tab_entries(viewport)
        end
    end
  end

  # Build a synthetic tab-bar aggregate from individual :tab type entries registered
  # by ScenicWidgets.TabBar. The TabBar widget registers one Entry per tab with:
  #   - type: :tab
  #   - id: :"tab_bar_#{uuid}"
  #   - label: the visible tab label (e.g. "untitled")
  #   - role: :selected_tab (active) or :tab (inactive)
  #   - value: the raw tab id (UUID string used as buffer id)
  # We reconstruct tab_count, tabs list, and selected_id from these entries.
  defp build_tab_bar_from_tab_entries(viewport) do
    case find_by_type_all_graphs(viewport, :tab) do
      {:ok, []} ->
        {:error, :not_found}

      {:ok, tab_entries} ->
        tab_list =
          Enum.map(tab_entries, fn entry ->
            sem = entry.semantic || %{}

            %{
              id: sem[:value] || entry.id,
              label: sem[:label] || entry.label || to_string(entry.content || "")
            }
          end)

        selected_entry =
          Enum.find(tab_entries, fn entry ->
            (entry.semantic || %{})[:role] == :selected_tab
          end)

        selected_id =
          if selected_entry do
            sem = selected_entry.semantic || %{}
            sem[:value] || selected_entry.id
          end

        {:ok,
         %{
           id: :tab_bar_derived,
           type: :tab_bar,
           content: nil,
           semantic: %{
             type: :tab_bar,
             tab_count: length(tab_list),
             tabs: tab_list,
             selected_id: selected_id
           },
           clickable: false
         }}
    end
  end

  # Read the plain-map aggregate entry written by TabBar.register_tab_bar_aggregate/3.
  # Returns {:ok, element} where element.semantic has :tab_count, :tabs, :selected_id.
  defp find_tab_bar_aggregate(viewport) do
    semantic_data = :ets.tab2list(viewport.semantic_table)

    result =
      Enum.find_value(semantic_data, fn
        {{_scene_name, :tab_bar_aggregate}, %{tab_count: _} = data} ->
          %{
            id: :tab_bar_aggregate,
            type: :tab_bar,
            content: nil,
            semantic: Map.put(data, :type, :tab_bar),
            clickable: false
          }

        _ ->
          nil
      end)

    case result do
      nil -> {:error, :not_found}
      elem -> {:ok, elem}
    end
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
  # TabBar Click Helpers (using semantic registration)
  # ===========================================================================

  @doc """
  Click on a tab by its label using the semantic clickable registration.
  Uses the aggregate tab bar metadata to find the tab ID, then clicks
  the semantically registered tab element.
  Returns {:ok, result} or {:error, reason}.
  """
  def click_tab_by_label(label) when is_binary(label) do
    with_viewport(fn viewport ->
      case find_tab_bar(viewport) do
        {:ok, tab_bar} ->
          semantic = tab_bar.semantic || %{}
          tabs = semantic[:tabs] || []

          # Find tab matching the label - prefer exact match, fall back to substring
          exact_match = Enum.find(tabs, fn tab ->
            to_string(tab[:label]) == label
          end)

          match = exact_match || Enum.find(tabs, fn tab ->
            tab_label = to_string(tab[:label])
            String.contains?(tab_label, label) or
              String.contains?(label, tab_label)
          end)

          if match do
            tab_id_str = to_string(match[:id])
            semantic_id = "tab_bar_#{tab_id_str}"
            Tools.click_element(%{"element_id" => semantic_id})
          else
            {:error, {:not_found, "No tab matching '#{label}'. Available: #{inspect(Enum.map(tabs, & &1[:label]))}"}}
          end

        _ ->
          {:error, :tab_bar_not_found}
      end
    end)
  end

  @doc """
  Click the close button on a tab by its label.
  Returns {:ok, result} or {:error, reason}.
  """
  def close_tab_by_label(label) when is_binary(label) do
    with_viewport(fn viewport ->
      case find_tab_bar(viewport) do
        {:ok, tab_bar} ->
          semantic = tab_bar.semantic || %{}
          tabs = semantic[:tabs] || []

          exact_match = Enum.find(tabs, fn tab ->
            to_string(tab[:label]) == label
          end)

          match = exact_match || Enum.find(tabs, fn tab ->
            tab_label = to_string(tab[:label])
            String.contains?(tab_label, label) or
              String.contains?(label, tab_label)
          end)

          if match do
            tab_id_str = to_string(match[:id])
            close_id = "tab_bar_close_#{tab_id_str}"
            Tools.click_element(%{"element_id" => close_id})
          else
            {:error, {:not_found, "No tab matching '#{label}'"}}
          end

        _ ->
          {:error, :tab_bar_not_found}
      end
    end)
  end

  # ===========================================================================
  # Selection Polling Helpers
  # ===========================================================================

  @doc """
  Wait for the active text buffer to have a non-nil selection.

  Polls the semantic viewport until a selection appears on the text buffer,
  or until `timeout` ms elapses.

  Returns `{:ok, buffer, selection}` where `selection` is a map with
  `:start` and `:end` keys (each a `{line, col}` tuple), or
  `{:error, :selection_timeout}` on timeout.
  """
  def wait_for_active_selection(timeout \\ 2000) do
    end_time = System.monotonic_time(:millisecond) + timeout
    do_wait_for_selection(end_time)
  end

  defp do_wait_for_selection(end_time) do
    case Scenic.ViewPort.info(:main_viewport) do
      {:ok, viewport} ->
        case find_text_buffer(viewport) do
          {:ok, buffer} ->
            selection = get_in(buffer, [:semantic, :selection])

            if selection do
              {:ok, buffer, selection}
            else
              retry_selection_wait(end_time)
            end

          _ ->
            retry_selection_wait(end_time)
        end

      _ ->
        retry_selection_wait(end_time)
    end
  end

  defp retry_selection_wait(end_time) do
    if System.monotonic_time(:millisecond) < end_time do
      Process.sleep(50)
      do_wait_for_selection(end_time)
    else
      {:error, :selection_timeout}
    end
  end

  # ===========================================================================
  # Dialog Visibility Helpers
  # ===========================================================================

  @doc """
  Check if the unsaved-changes confirmation dialog is currently visible.

  Returns `true` when the ConfirmDialog titled "Unsaved Changes" is rendered in
  the viewport (i.e. the user is being prompted about a dirty buffer close).
  Returns `false` otherwise.

  Used in integration tests to assert or refute dialog presence without
  coupling to a specific semantic element ID.
  """
  def unsaved_prompt_visible? do
    ScenicMcp.Query.text_visible?("Unsaved Changes")
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

  @doc """
  Clear all buffers and create a fresh empty buffer.
  Used in test setup to ensure clean state.
  """
  def clear_all_buffers_and_create_fresh do
    # Try to close all buffers except one
    tab_labels = get_tab_labels()

    # Close all tabs except the first one
    Enum.each(Enum.drop(tab_labels, 1), fn label ->
      close_tab_by_label(label)
      Process.sleep(100)
    end)

    # Clear content of remaining buffer
    clear_current_buffer()

    # Note: If all buffers were closed (shouldn't happen in normal test flow),
    # we cannot create a new one here — SemanticHelpers is a black-box helper
    # and must not call internal Quillex APIs. Test setup should ensure at least
    # one buffer always exists before calling this helper.
    :ok
  end

  @doc """
  Clear content of the current active buffer.
  """
  def clear_current_buffer do
    # Select all and delete
    Probes.send_keys("a", [:ctrl])
    Process.sleep(50)
    Probes.send_keys("backspace", [])
    Process.sleep(100)
  end
end
