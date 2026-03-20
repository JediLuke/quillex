defmodule Quillex.TestHelpers.SemanticHelpersTest do
  @moduledoc """
  Unit tests for SemanticHelpers tab bar query functions.

  These tests verify that find_tab_bar/1 and its dependents correctly
  derive tab bar information from individual :tab type entries registered
  by ScenicWidgets.TabBar (which does NOT write a :tab_bar_aggregate entry).
  """
  use ExUnit.Case, async: false

  alias Quillex.TestHelpers.SemanticHelpers

  # Helper to build a fake Scenic.Semantic.Compiler.Entry for a tab
  defp tab_entry(opts) do
    uuid = Keyword.fetch!(opts, :uuid)
    label = Keyword.get(opts, :label, "untitled")
    role = Keyword.get(opts, :role, :tab)
    index = Keyword.get(opts, :index, 0)

    %Scenic.Semantic.Compiler.Entry{
      id: String.to_atom("tab_bar_#{uuid}"),
      type: :tab,
      module: nil,
      parent_id: nil,
      children: [],
      label: label,
      role: role,
      value: uuid,
      clickable: true,
      focusable: false,
      hidden: false,
      z_index: 0,
      local_bounds: %{left: index * 100, top: 0, width: 100, height: 30},
      screen_bounds: %{left: index * 100, top: 0, width: 100, height: 30}
    }
  end

  # Helper to build a fake viewport with a populated semantic table
  defp viewport_with_tabs(tab_specs) do
    table = :ets.new(:test_semantic_tab_table, [:set, :public])

    tab_specs
    |> Enum.with_index()
    |> Enum.each(fn {{uuid, label, role}, index} ->
      entry = tab_entry(uuid: uuid, label: label, role: role, index: index)
      semantic_id = String.to_atom("tab_bar_#{uuid}")
      :ets.insert(table, {{:tab_bar_scene, semantic_id}, entry})
    end)

    {%{semantic_table: table}, table}
  end

  describe "find_tab_bar/1 via build_tab_bar_from_tab_entries fallback" do
    test "returns error when semantic table has no tab entries" do
      table = :ets.new(:test_empty_semantic_table, [:set, :public])
      on_exit(fn -> :ets.delete(table) end)

      viewport = %{semantic_table: table}

      assert {:error, :not_found} = SemanticHelpers.find_tab_bar(viewport)
    end

    test "builds tab bar aggregate from single tab entry" do
      {viewport, table} =
        viewport_with_tabs([
          {"uuid-abc", "untitled", :selected_tab}
        ])

      on_exit(fn -> :ets.delete(table) end)

      assert {:ok, tab_bar} = SemanticHelpers.find_tab_bar(viewport)
      assert tab_bar.semantic[:tab_count] == 1
      assert tab_bar.semantic[:selected_id] == "uuid-abc"

      tab_labels = Enum.map(tab_bar.semantic[:tabs], & &1[:label])
      assert tab_labels == ["untitled"]
    end

    test "builds tab bar from two tabs with correct selected_id" do
      {viewport, table} =
        viewport_with_tabs([
          {"uuid-1", "first.ex", :tab},
          {"uuid-2", "second.ex", :selected_tab}
        ])

      on_exit(fn -> :ets.delete(table) end)

      assert {:ok, tab_bar} = SemanticHelpers.find_tab_bar(viewport)
      assert tab_bar.semantic[:tab_count] == 2
      assert tab_bar.semantic[:selected_id] == "uuid-2"
    end

    test "tabs list contains id and label fields" do
      {viewport, table} =
        viewport_with_tabs([
          {"uuid-x", "foo.ex", :selected_tab},
          {"uuid-y", "bar.ex", :tab}
        ])

      on_exit(fn -> :ets.delete(table) end)

      assert {:ok, tab_bar} = SemanticHelpers.find_tab_bar(viewport)
      tabs = tab_bar.semantic[:tabs]
      assert length(tabs) == 2

      # Each tab must have :id and :label
      assert Enum.all?(tabs, &(Map.has_key?(&1, :id) and Map.has_key?(&1, :label)))

      # IDs are the raw buffer UUIDs (for click_tab_by_label to construct semantic_id)
      ids = Enum.map(tabs, & &1[:id]) |> Enum.sort()
      assert ids == ["uuid-x", "uuid-y"]
    end
  end

  describe "get_tab_count/1" do
    test "returns 0-equivalent (nil) when no tabs" do
      table = :ets.new(:test_tab_count_empty, [:set, :public])
      on_exit(fn -> :ets.delete(table) end)

      viewport = %{semantic_table: table}
      # get_tab_count returns nil when find_tab_bar fails, tests use || 0
      assert SemanticHelpers.get_tab_count(viewport) == nil
    end

    test "returns count of tabs from :tab entries" do
      {viewport, table} =
        viewport_with_tabs([
          {"uuid-1", "a.ex", :selected_tab},
          {"uuid-2", "b.ex", :tab},
          {"uuid-3", "c.ex", :tab}
        ])

      on_exit(fn -> :ets.delete(table) end)

      assert SemanticHelpers.get_tab_count(viewport) == 3
    end
  end

  describe "get_tab_labels/1" do
    test "returns empty list when no tabs" do
      table = :ets.new(:test_labels_empty, [:set, :public])
      on_exit(fn -> :ets.delete(table) end)

      viewport = %{semantic_table: table}
      assert SemanticHelpers.get_tab_labels(viewport) == []
    end

    test "returns list of labels from :tab entries" do
      {viewport, table} =
        viewport_with_tabs([
          {"uuid-1", "main.ex", :selected_tab},
          {"uuid-2", "README.md", :tab}
        ])

      on_exit(fn -> :ets.delete(table) end)

      labels = SemanticHelpers.get_tab_labels(viewport) |> Enum.sort()
      assert labels == ["README.md", "main.ex"]
    end
  end

  describe "get_selected_tab_label/1" do
    test "returns nil when no tabs" do
      table = :ets.new(:test_selected_empty, [:set, :public])
      on_exit(fn -> :ets.delete(table) end)

      viewport = %{semantic_table: table}
      assert SemanticHelpers.get_selected_tab_label(viewport) == nil
    end

    test "returns label of the :selected_tab entry" do
      {viewport, table} =
        viewport_with_tabs([
          {"uuid-1", "active_file.ex", :selected_tab},
          {"uuid-2", "other_file.ex", :tab}
        ])

      on_exit(fn -> :ets.delete(table) end)

      assert SemanticHelpers.get_selected_tab_label(viewport) == "active_file.ex"
    end

    test "returns nil when no tab has :selected_tab role" do
      {viewport, table} =
        viewport_with_tabs([
          {"uuid-1", "a.ex", :tab},
          {"uuid-2", "b.ex", :tab}
        ])

      on_exit(fn -> :ets.delete(table) end)

      # No selected_tab → selected_id is nil → Enum.find returns nil → returns nil
      assert SemanticHelpers.get_selected_tab_label(viewport) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # entry_to_element/1 custom metadata propagation
  # Tests for the case where entry.value is a map containing rich custom
  # metadata (buffer_id, cursor_position, selection, scroll, etc.)
  # ---------------------------------------------------------------------------

  # Build a viewport whose semantic table contains a single Format 2 Entry.
  defp viewport_with_format2_entry(entry_id, entry) do
    table = :ets.new(:"test_f2_entry_#{:erlang.unique_integer([:positive])}", [:set, :public])
    :ets.insert(table, {{:test_scene, entry_id}, entry})
    {%{semantic_table: table}, table}
  end

  describe "entry_to_element/1 custom metadata propagation" do
    test "custom fields in entry.value map are merged into semantic" do
      entry = %Scenic.Semantic.Compiler.Entry{
        id: :buffer_semantic,
        type: :text_buffer,
        module: nil,
        parent_id: nil,
        children: [],
        label: nil,
        role: :textbox,
        value: %{
          buffer_id: "uuid-abc-123",
          cursor_position: {2, 10},
          field_id: :buffer_pane
        },
        clickable: false,
        focusable: false,
        hidden: false,
        z_index: 0,
        local_bounds: %{left: 0, top: 0, width: 600, height: 400},
        screen_bounds: %{left: 0, top: 40, width: 600, height: 400}
      }

      {viewport, table} = viewport_with_format2_entry(:buffer_semantic, entry)
      on_exit(fn -> :ets.delete(table) end)

      {:ok, elements} = SemanticHelpers.find_by_type_all_graphs(viewport, :text_buffer)
      assert length(elements) == 1

      elem = List.first(elements)
      assert get_in(elem, [:semantic, :buffer_id]) == "uuid-abc-123"
      assert get_in(elem, [:semantic, :cursor_position]) == {2, 10}
      assert get_in(elem, [:semantic, :field_id]) == :buffer_pane
    end

    test "standard fields are preserved when value is a custom metadata map" do
      entry = %Scenic.Semantic.Compiler.Entry{
        id: :text_buf_entry,
        type: :text_buffer,
        module: nil,
        parent_id: nil,
        children: [],
        label: "buffer label",
        role: :textbox,
        value: %{buffer_id: "uuid-xyz", scroll: %{offset_x: 0, offset_y: 50}},
        clickable: true,
        focusable: false,
        hidden: false,
        z_index: 0,
        local_bounds: %{left: 0, top: 0, width: 600, height: 400},
        screen_bounds: %{left: 0, top: 40, width: 600, height: 400}
      }

      {viewport, table} = viewport_with_format2_entry(:text_buf_entry, entry)
      on_exit(fn -> :ets.delete(table) end)

      {:ok, elements} = SemanticHelpers.find_by_type_all_graphs(viewport, :text_buffer)
      elem = List.first(elements)
      sem = elem.semantic

      # Standard fields must be preserved
      assert sem[:type] == :text_buffer
      assert sem[:label] == "buffer label"
      assert sem[:role] == :textbox
      assert sem[:clickable] == true

      # Custom fields accessible directly
      assert sem[:buffer_id] == "uuid-xyz"
      assert sem[:scroll] == %{offset_x: 0, offset_y: 50}
    end

    test "standard fields take priority over conflicting keys in value map" do
      entry = %Scenic.Semantic.Compiler.Entry{
        id: :conflict_entry,
        type: :text_buffer,
        module: nil,
        parent_id: nil,
        children: [],
        label: "correct label",
        role: :textbox,
        # value map also has 'type' and 'label' keys - base_semantic must win
        value: %{type: :wrong_type, label: "wrong label", buffer_id: "uuid-override"},
        clickable: false,
        focusable: false,
        hidden: false,
        z_index: 0,
        local_bounds: %{left: 0, top: 0, width: 600, height: 400},
        screen_bounds: %{left: 0, top: 40, width: 600, height: 400}
      }

      {viewport, table} = viewport_with_format2_entry(:conflict_entry, entry)
      on_exit(fn -> :ets.delete(table) end)

      {:ok, elements} = SemanticHelpers.find_by_type_all_graphs(viewport, :text_buffer)
      elem = List.first(elements)
      sem = elem.semantic

      # Standard fields win
      assert sem[:type] == :text_buffer
      assert sem[:label] == "correct label"
      # Custom field from value still accessible
      assert sem[:buffer_id] == "uuid-override"
    end

    test "non-map entry.value does not affect standard semantic fields" do
      entry = %Scenic.Semantic.Compiler.Entry{
        id: :"tab_bar_some-uuid",
        type: :tab,
        module: nil,
        parent_id: nil,
        children: [],
        label: "file.ex",
        role: :selected_tab,
        value: "some-uuid-string",
        clickable: true,
        focusable: false,
        hidden: false,
        z_index: 0,
        local_bounds: %{left: 0, top: 0, width: 100, height: 30},
        screen_bounds: %{left: 0, top: 0, width: 100, height: 30}
      }

      {viewport, table} = viewport_with_format2_entry(:"tab_bar_some-uuid", entry)
      on_exit(fn -> :ets.delete(table) end)

      {:ok, elements} = SemanticHelpers.find_by_type_all_graphs(viewport, :tab)
      elem = List.first(elements)
      sem = elem.semantic

      # Standard fields present
      assert sem[:type] == :tab
      assert sem[:label] == "file.ex"
      assert sem[:role] == :selected_tab
      assert sem[:value] == "some-uuid-string"
      assert sem[:clickable] == true

      # No unexpected extra keys from string value
      refute Map.has_key?(sem, :buffer_id)
      refute Map.has_key?(sem, :cursor_position)
    end
  end

  describe "click_tab_by_label/1 semantic_id construction" do
    test "tabs list uses raw UUID as :id so semantic_id matches TabBar registration" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"

      {viewport, table} =
        viewport_with_tabs([
          {uuid, "some_file.ex", :selected_tab}
        ])

      on_exit(fn -> :ets.delete(table) end)

      assert {:ok, tab_bar} = SemanticHelpers.find_tab_bar(viewport)
      tab = List.first(tab_bar.semantic[:tabs])

      # The :id field must be the raw UUID so click_tab_by_label constructs
      # semantic_id = "tab_bar_#{uuid}" which matches the atom :"tab_bar_#{uuid}"
      # that ScenicWidgets.TabBar registered.
      assert tab[:id] == uuid
      assert "tab_bar_#{tab[:id]}" == "tab_bar_#{uuid}"
    end
  end

  # Helper to build a fake viewport containing a text buffer element with
  # optional selection and buffer_id in its semantic metadata.
  defp viewport_with_text_buffer(opts \\ []) do
    buffer_id = Keyword.get(opts, :buffer_id)
    selection = Keyword.get(opts, :selection)
    content = Keyword.get(opts, :content, "Hello World")

    table = :ets.new(:test_text_buffer_table, [:set, :public])

    semantic =
      %{type: :text_buffer, field_id: :buffer_pane, editable: true, multiline: true}
      |> then(fn m -> if buffer_id, do: Map.put(m, :buffer_id, buffer_id), else: m end)
      |> then(fn m -> if selection, do: Map.put(m, :selection, selection), else: m end)

    elem = %{
      id: :buffer_pane,
      type: :text_buffer,
      content: content,
      semantic: semantic
    }

    :ets.insert(table, {:main_graph, %{elements: %{buffer_pane: elem}, timestamp: 1000}})

    {%{semantic_table: table}, table}
  end

  describe "find_text_buffer/1 with buffer_id in semantic metadata" do
    test "returns buffer_id from semantic when present" do
      uuid = "abc-123-def-456"
      {viewport, table} = viewport_with_text_buffer(buffer_id: uuid)
      on_exit(fn -> :ets.delete(table) end)

      assert {:ok, buffer} = SemanticHelpers.find_text_buffer(viewport)
      assert get_in(buffer, [:semantic, :buffer_id]) == uuid
    end

    test "returns nil buffer_id when not set (backwards compat)" do
      {viewport, table} = viewport_with_text_buffer()
      on_exit(fn -> :ets.delete(table) end)

      assert {:ok, buffer} = SemanticHelpers.find_text_buffer(viewport)
      assert get_in(buffer, [:semantic, :buffer_id]) == nil
    end

    test "find_text_buffer/2 with matching buffer_id finds the right buffer" do
      uuid = "match-this-uuid"
      {viewport, table} = viewport_with_text_buffer(buffer_id: uuid, content: "Correct buffer")
      on_exit(fn -> :ets.delete(table) end)

      assert {:ok, buffer} = SemanticHelpers.find_text_buffer(viewport, uuid)
      assert buffer.content == "Correct buffer"
    end
  end

  describe "wait_for_active_selection/1 prerequisite: selection in semantic" do
    # wait_for_active_selection polls Scenic.ViewPort.info(:main_viewport) and
    # cannot be called in unit tests. These tests verify the underlying mechanism:
    # that when a text buffer has a selection in its semantic data, find_text_buffer
    # returns it correctly — which is the data path wait_for_active_selection uses.

    test "find_text_buffer returns buffer with selection when selection present" do
      selection = %{start: {1, 1}, end: {1, 6}}
      {viewport, table} = viewport_with_text_buffer(selection: selection, content: "Hello World")
      on_exit(fn -> :ets.delete(table) end)

      assert {:ok, buffer} = SemanticHelpers.find_text_buffer(viewport)
      assert get_in(buffer, [:semantic, :selection]) == selection
    end

    test "find_text_buffer returns buffer with nil selection when no selection" do
      {viewport, table} = viewport_with_text_buffer()
      on_exit(fn -> :ets.delete(table) end)

      assert {:ok, buffer} = SemanticHelpers.find_text_buffer(viewport)
      assert get_in(buffer, [:semantic, :selection]) == nil
    end

    test "buffer content is accessible from element returned by find_text_buffer" do
      selection = %{start: {1, 3}, end: {1, 8}}
      content = "Sphinx of black quartz"
      {viewport, table} = viewport_with_text_buffer(selection: selection, content: content)
      on_exit(fn -> :ets.delete(table) end)

      assert {:ok, buffer} = SemanticHelpers.find_text_buffer(viewport)
      assert buffer.content == content
      assert get_in(buffer, [:semantic, :selection]) == selection
    end
  end
end
