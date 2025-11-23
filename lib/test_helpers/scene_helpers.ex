defmodule Quillex.TestHelpers.SceneHelpers do
  @moduledoc """
  Enhanced helpers for testing Scenic applications with scene introspection.
  
  Provides purpose-built assertions and utilities for spex tests that leverage
  the new scene introspection capabilities in Scenic.DevTools.
  """
  
  import ExUnit.Assertions
  
  @doc """
  Assert scene hierarchy is properly established.
  
  Options:
    * `:timeout` - Maximum time to wait (default: 5000ms)
    * `:min_scenes` - Minimum expected scenes (default: 2)
  """
  def assert_scene_ready(viewport_name \\ :main_viewport, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    
    case Scenic.DevTools.wait_for_scene_hierarchy(viewport_name, opts) do
      {:ok, data} ->
        assert Map.has_key?(data, "_root_"), "Should have root scene"
        assert Map.has_key?(data, "_main_"), "Should have main scene"
        
        root = data["_root_"]
        main = data["_main_"]
        
        assert main.parent == "_root_", "Main scene should be child of root"
        assert "_main_" in root.children, "Root should list main as child"
        
        {:ok, data}
        
      {:error, reason} ->
        # Run diagnostics to help debug
        Scenic.DevTools.diagnose_scene_issues(viewport_name)
        flunk("Scene hierarchy not established within #{timeout}ms: #{reason}")
    end
  end
  
  @doc """
  Assert a component exists with expected properties.
  """
  def assert_component_exists(scene_data, component_type, properties \\ []) do
    components = find_components_by_type(scene_data, component_type)
    
    assert length(components) > 0, 
           "Expected at least one #{component_type} component, found none"
    
    if properties != [] do
      component = hd(components)
      
      Enum.each(properties, fn {key, expected} ->
        actual = get_in(component, [:semantic, key])
        assert actual == expected,
               "Component #{component_type} #{key} should be #{inspect(expected)}, got #{inspect(actual)}"
      end)
    end
    
    components
  end
  
  @doc """
  Capture scene state for comparison.
  """
  def capture_scene_snapshot(label, viewport_name \\ :main_viewport) do
    %{
      label: label,
      timestamp: System.monotonic_time(:microsecond),
      scene_data: Scenic.DevTools.raw_scene_script(viewport_name),
      semantic_data: Scenic.DevTools.raw_semantic(viewport_name),
      element_count: count_total_elements(viewport_name),
      graph_count: count_graphs(viewport_name)
    }
  end
  
  @doc """
  Assert scene remains stable during an operation.
  """
  def assert_scene_stable_during(viewport_name \\ :main_viewport, fun) do
    {result, changes} = Scenic.DevTools.track_changes(viewport_name, fun)
    
    assert changes.added_graphs == [], 
           "No graphs should be added, but found: #{inspect(changes.added_graphs)}"
    assert changes.removed_graphs == [], 
           "No graphs should be removed, but found: #{inspect(changes.removed_graphs)}"
    assert changes.hierarchy_changes.parent_changes == [],
           "Parent relationships should not change"
    
    result
  end
  
  @doc """
  Assert specific scene changes occurred.
  """
  def assert_scene_changed(before_snapshot, after_snapshot, expected_changes) do
    actual_changes = diff_snapshots(before_snapshot, after_snapshot)
    
    Enum.each(expected_changes, fn
      {:graphs_added, count} ->
        assert length(actual_changes.added_graphs) == count,
               "Expected #{count} graphs added, got #{length(actual_changes.added_graphs)}"
               
      {:graphs_removed, count} ->
        assert length(actual_changes.removed_graphs) == count,
               "Expected #{count} graphs removed, got #{length(actual_changes.removed_graphs)}"
               
      {:elements_added, count} ->
        element_diff = actual_changes.element_changes.total_after - 
                       actual_changes.element_changes.total_before
        assert element_diff == count,
               "Expected #{count} elements added, got #{element_diff}"
               
      {:graph_modified, graph_key} ->
        assert graph_key in actual_changes.modified_graphs,
               "Expected graph #{graph_key} to be modified"
    end)
  end
  
  @doc """
  Find components by semantic type across all scenes.
  """
  def find_components_by_type(scene_data, component_type) do
    scene_data
    |> Map.values()
    |> Enum.flat_map(fn scene ->
      scene.elements
      |> Map.values()
      |> Enum.filter(fn element ->
        get_in(element, [:semantic, :type]) == component_type
      end)
    end)
  end
  
  @doc """
  Assert text buffer contains expected content.
  """
  def assert_text_buffer_contains(scene_data, expected_text) do
    text_buffers = find_components_by_type(scene_data, :text_buffer)
    
    buffer_contents = Enum.map(text_buffers, fn buffer ->
      get_in(buffer, [:semantic, :content]) || ""
    end)
    
    assert Enum.any?(buffer_contents, &String.contains?(&1, expected_text)),
           "No text buffer contains '#{expected_text}'. Found: #{inspect(buffer_contents)}"
  end
  
  @doc """
  Measure performance of scene updates.
  """
  def measure_scene_update(viewport_name \\ :main_viewport, fun) do
    {result, changes} = Scenic.DevTools.track_changes(viewport_name, fun)
    
    %{
      result: result,
      duration_ms: changes.duration_us / 1000,
      graphs_changed: length(changes.modified_graphs),
      elements_changed: changes.element_changes.total_after - 
                       changes.element_changes.total_before
    }
  end
  
  @doc """
  Run function with enhanced error reporting.
  """
  def with_scene_debugging(viewport_name \\ :main_viewport, fun) do
    try do
      fun.()
    rescue
      error ->
        IO.puts("\n❌ Error occurred during test:")
        IO.puts("  #{Exception.format(:error, error)}")
        
        IO.puts("\n📸 Scene state at time of error:")
        Scenic.DevTools.introspect(viewport_name)
        Scenic.DevTools.element_heatmap(viewport_name)
        
        reraise error, __STACKTRACE__
    end
  end
  
  @doc """
  Assert scene hierarchy matches expected structure.
  """
  def assert_hierarchy_structure(scene_data, expected_structure) do
    actual_structure = extract_minimal_hierarchy(scene_data)
    
    Enum.each(expected_structure, fn {key, expected_info} ->
      assert Map.has_key?(actual_structure, key),
             "Expected scene #{key} in hierarchy"
             
      actual = actual_structure[key]
      
      if Map.has_key?(expected_info, :parent) do
        assert actual.parent == expected_info.parent,
               "Scene #{key} should have parent #{expected_info.parent}, got #{actual.parent}"
      end
      
      if Map.has_key?(expected_info, :depth) do
        assert actual.depth == expected_info.depth,
               "Scene #{key} should be at depth #{expected_info.depth}, got #{actual.depth}"
      end
      
      if Map.has_key?(expected_info, :children) do
        assert MapSet.new(actual.children) == MapSet.new(expected_info.children),
               "Scene #{key} children mismatch"
      end
    end)
  end
  
  # Private helpers
  
  defp count_total_elements(viewport_name) do
    Scenic.DevTools.raw_scene_script(viewport_name)
    |> Map.values()
    |> Enum.map(fn scene -> map_size(scene.elements) end)
    |> Enum.sum()
  end
  
  defp count_graphs(viewport_name) do
    Scenic.DevTools.raw_scene_script(viewport_name)
    |> map_size()
  end
  
  defp diff_snapshots(before_snapshot, after_snapshot) do
    Scenic.DevTools.diff_scenes(before_snapshot.scene_data, after_snapshot.scene_data)
    |> Map.put(:duration_us, after_snapshot.timestamp - before_snapshot.timestamp)
  end
  
  defp extract_minimal_hierarchy(scene_data) do
    Map.new(scene_data, fn {key, scene} ->
      {key, %{
        parent: scene.parent,
        depth: scene.depth,
        children: scene.children
      }}
    end)
  end
end