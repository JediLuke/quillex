defmodule QuillEx.RootSceneTest do
  use ExUnit.Case
  alias QuillEx.RootScene

  # Minimal scene struct needed by the handlers under test.
  # RootScene functions only read scene.assigns.state and scene.assigns.graph;
  # they never call Scenic internals on it, so a plain map is enough.
  defp bare_scene do
    %{
      assigns: %{
        state: %QuillEx.RootScene.State{
          active_buf: nil,
          show_line_numbers: true,
          word_wrap: false
        },
        graph: %Scenic.Graph{}
      }
    }
  end

  describe "run_verification keyboard shortcut" do
    test "Ctrl+V+F returns {:noreply, scene} unchanged" do
      scene = bare_scene()
      result = RootScene.handle_input({:key, {"f", 1, ["ctrl", "v"]}}, nil, scene)
      assert {:noreply, ^scene} = result
    end

    test "alternative modifier order Ctrl+V+F returns {:noreply, scene} unchanged" do
      scene = bare_scene()
      result = RootScene.handle_input({:key, {"f", 1, ["v", "ctrl"]}}, nil, scene)
      assert {:noreply, ^scene} = result
    end
  end

  describe "handle_cast :run_verification" do
    test "returns {:noreply, scene} when no buffer process is running" do
      scene = bare_scene()
      result = RootScene.handle_cast({:action, :run_verification}, scene)
      assert {:noreply, ^scene} = result
    end

    test "returns {:noreply, scene} when fetch_buf raises (buffer process not found)" do
      # Point active_buf at a fake BufRef whose UUID has no registered buffer process.
      # call_buffer/2 raises when the Registry lookup returns [] — our try/catch in the
      # handler converts that raise/exit into {:error, reason} and logs at :debug level.
      fake_buf_ref = %Quillex.Structs.BufState.BufRef{uuid: "nonexistent-uuid-test", name: "ghost.txt"}
      scene = %{
        assigns: %{
          state: %QuillEx.RootScene.State{
            active_buf: fake_buf_ref,
            show_line_numbers: true,
            word_wrap: false
          },
          graph: %Scenic.Graph{}
        }
      }
      result = RootScene.handle_cast({:action, :run_verification}, scene)
      assert {:noreply, ^scene} = result
    end
  end

  # ---------------------------------------------------------------------------
  # Ctrl+H / Find & Replace
  # ---------------------------------------------------------------------------
  #
  # The handle_input clause for Ctrl+H calls show_search_bar/2 which relies on
  # live Scenic.Scene internals (fetch_child, push_graph, etc.) and cannot be
  # exercised in a pure unit test without a running scene process.  Full UI
  # behaviour is covered by test/spex/quillex/12_replace_spex.exs.
  #
  # What we CAN unit-test here is:
  #   1. The Ctrl+H clause is defined (not swallowed by the catch-all).
  #   2. The reducer's :open_replace / :close_replace actions — these are pure
  #      state transforms and carry zero Scenic dependencies.

  describe "Ctrl+H handle_input clause" do
    test "Ctrl+H is NOT routed to the catch-all handler" do
      # The catch-all returns {:noreply, scene} without touching Scenic.
      # The Ctrl+H clause calls show_search_bar, which tries to call
      # Scenic.Scene.fetch_child/2 with a non-Scene struct and therefore
      # raises FunctionClauseError.  That proves the *correct* clause fired.
      scene = bare_scene()

      assert_raise FunctionClauseError, fn ->
        RootScene.handle_input({:key, {"h", 1, ["ctrl"]}}, nil, scene)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Ctrl+F — Find (search-only)
  # ---------------------------------------------------------------------------
  #
  # The Ctrl+F handler calls show_search_bar/1 (no replace_mode: true), which
  # also calls Scenic.Scene.fetch_child/2 and raises FunctionClauseError on a
  # bare map — proving the correct clause fired.
  # Full UI behaviour is covered by test/spex/quillex/06_find_spex.exs and
  # test/spex/quillex/13_menu_close_outside_click_spex.exs.

  describe "Ctrl+F handle_input clause" do
    test "Ctrl+F is NOT routed to the catch-all handler" do
      scene = bare_scene()
      assert_raise FunctionClauseError, fn ->
        RootScene.handle_input({:key, {"f", 1, ["ctrl"]}}, nil, scene)
      end
    end
  end

  describe "RootScene.Reducer :open_replace action" do
    test "sets show_search_bar and show_replace to true" do
      state = %QuillEx.RootScene.State{show_search_bar: false, show_replace: false}
      new_state = QuillEx.RootScene.Reducer.process(state, :open_replace)
      assert new_state.show_search_bar == true
      assert new_state.show_replace == true
    end

    test "is idempotent when bar is already open" do
      state = %QuillEx.RootScene.State{show_search_bar: true, show_replace: true}
      new_state = QuillEx.RootScene.Reducer.process(state, :open_replace)
      assert new_state.show_search_bar == true
      assert new_state.show_replace == true
    end
  end

  # ---------------------------------------------------------------------------
  # Ctrl+N — New Buffer
  # ---------------------------------------------------------------------------
  #
  # The Ctrl+N handler calls handle_cast({:action, :new_buffer}) which reaches
  # the BufferManager GenServer.  Without a running BufferManager, Wormhole
  # (used inside process_actions) absorbs the exit and returns {:noreply, scene}.
  # Full UI behaviour is covered by test/spex/quillex/14_keyboard_shortcuts_spex.exs.

  describe "Ctrl+N handle_input clause" do
    test "Ctrl+N fires the new_buffer handler without crashing (smoke test)" do
      scene = bare_scene()
      # Wormhole absorbs the missing-GenServer exit; result mirrors the error path.
      result = RootScene.handle_input({:key, {"n", 1, ["ctrl"]}}, nil, scene)
      assert match?({:noreply, _}, result)
    end
  end

  # ---------------------------------------------------------------------------
  # Ctrl+O — Open File
  # ---------------------------------------------------------------------------
  #
  # The Ctrl+O handler calls show_file_picker/1 which immediately calls
  # Scenic.Scene.assign/2.  With a bare map (not a real %Scenic.Scene{}),
  # assign/2 raises FunctionClauseError — the same proof-of-clause-fired
  # technique used for the Ctrl+H test above.
  # Full UI behaviour is covered by test/spex/quillex/14_keyboard_shortcuts_spex.exs.

  describe "Ctrl+O handle_input clause" do
    test "Ctrl+O is NOT routed to the catch-all handler" do
      scene = bare_scene()
      assert_raise FunctionClauseError, fn ->
        RootScene.handle_input({:key, {"o", 1, ["ctrl"]}}, nil, scene)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Ctrl+W — Close Buffer
  # ---------------------------------------------------------------------------
  #
  # The Ctrl+W handler calls handle_cast({:action, :close_active_buffer}).
  # With active_buf: nil the Reducer no-ops.  Depending on whether Wormhole
  # swallows the Renderizer or push_graph raises, the test process may receive
  # {:noreply, _} or FunctionClauseError — both mean the correct clause fired.
  #
  # The :close_active_buffer Reducer action is pure and tested thoroughly below.
  # Full UI behaviour is covered by test/spex/quillex/14_keyboard_shortcuts_spex.exs.

  describe "Ctrl+W handle_input clause" do
    test "Ctrl+W with nil active_buf does not crash the test process" do
      scene = bare_scene()
      try do
        result = RootScene.handle_input({:key, {"w", 1, ["ctrl"]}}, nil, scene)
        assert match?({:noreply, _}, result)
      rescue
        FunctionClauseError -> :ok  # push_graph on bare map — correct clause fired
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Reducer :close_active_buffer — pure unit tests
  # ---------------------------------------------------------------------------

  describe "RootScene.Reducer :close_active_buffer action" do
    test "with nil active_buf returns state unchanged (no-op)" do
      state = %QuillEx.RootScene.State{active_buf: nil, buffers: []}
      new_state = QuillEx.RootScene.Reducer.process(state, :close_active_buffer)
      assert new_state == state
    end

    test "removes the active buffer from the buffers list" do
      buf1 = %Quillex.Structs.BufState.BufRef{uuid: "buf-1", name: "file.txt"}
      buf2 = %Quillex.Structs.BufState.BufRef{uuid: "buf-2", name: "other.txt"}
      state = %QuillEx.RootScene.State{active_buf: buf1, buffers: [buf1, buf2]}
      new_state = QuillEx.RootScene.Reducer.process(state, :close_active_buffer)
      refute Enum.any?(new_state.buffers, &(&1.uuid == "buf-1"))
      assert Enum.any?(new_state.buffers, &(&1.uuid == "buf-2"))
    end

    test "switches active_buf to another buffer after closing the active one" do
      buf1 = %Quillex.Structs.BufState.BufRef{uuid: "buf-1", name: "first.txt"}
      buf2 = %Quillex.Structs.BufState.BufRef{uuid: "buf-2", name: "second.txt"}
      state = %QuillEx.RootScene.State{active_buf: buf1, buffers: [buf1, buf2]}
      new_state = QuillEx.RootScene.Reducer.process(state, :close_active_buffer)
      assert new_state.active_buf.uuid == "buf-2"
    end

    test "closing the only remaining buffer is a no-op (cannot close last buffer)" do
      buf1 = %Quillex.Structs.BufState.BufRef{uuid: "only-buf", name: "last.txt"}
      state = %QuillEx.RootScene.State{active_buf: buf1, buffers: [buf1]}
      new_state = QuillEx.RootScene.Reducer.process(state, :close_active_buffer)
      assert length(new_state.buffers) == 1
      assert new_state.active_buf == buf1
    end
  end

  describe "RootScene.Reducer :close_replace action" do
    test "clears show_search_bar, show_replace, and search state" do
      state = %QuillEx.RootScene.State{
        show_search_bar: true,
        show_replace: true,
        search_query: "hello",
        search_current_match: 2,
        search_total_matches: 5
      }
      new_state = QuillEx.RootScene.Reducer.process(state, :close_replace)
      assert new_state.show_search_bar == false
      assert new_state.show_replace == false
      assert new_state.search_query == ""
      assert new_state.search_current_match == 0
      assert new_state.search_total_matches == 0
    end

    test "is idempotent when bar is already closed" do
      state = %QuillEx.RootScene.State{
        show_search_bar: false, show_replace: false,
        search_query: "", search_current_match: 0, search_total_matches: 0
      }
      new_state = QuillEx.RootScene.Reducer.process(state, :close_replace)
      assert new_state.show_search_bar == false
      assert new_state.show_replace == false
    end
  end
end
