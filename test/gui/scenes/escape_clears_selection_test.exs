defmodule Quillex.RootScene.EscapeClearsSelectionTest do
  @moduledoc """
  Escape's lowest-precedence meaning: throw the selection away.

  Two halves. The first is the precedence decision on its own — a pure
  predicate, so every branch of "does anything else on screen own this Escape?"
  is one cheap assertion. The second drives a real buffer through the actual
  `handle_input/3` clause, because a predicate that nothing calls is worth
  nothing.

  There is deliberately no case here for a top-bar menu being open. The
  IconMenu CAPTURES `:key` for as long as a dropdown is up, so that Escape
  never reaches this scene to be judged — no gate is involved and nothing here
  could assert on it. 69_escape_clears_selection_spex.exs checks that in the
  running app, which is the only place it is observable.
  """
  use ExUnit.Case, async: false

  alias Quillex.RootScene
  alias Quillex.RootScene.State

  # Minimal scene struct the handler under test needs. Clearing a selection
  # never dirties the buffer, so the tab-bar update short-circuits and no
  # Scenic internals are touched — a plain map is enough, exactly as in
  # qlx_root_scene_test.exs.
  defp scene_with(state_overrides, buffers) do
    %{
      assigns: %{
        state: struct(%State{buffers: buffers}, state_overrides),
        graph: %Scenic.Graph{}
      }
    }
  end

  # ---------------------------------------------------------------------------
  # The precedence decision
  # ---------------------------------------------------------------------------

  describe "escape_clears_selection?/1" do
    test "an idle editor with the keyboard on the buffer: yes" do
      assert RootScene.escape_clears_selection?(%State{})
    end

    test "the project search pane is open: no, even when the buffer has the keyboard" do
      # The pane takes Escape whether or not it is focused, so it being open at
      # all is enough to defer to it.
      refute RootScene.escape_clears_selection?(%State{
               show_project_search: true,
               keyboard_owner: :buffer
             })
    end

    test "the side pane holds the keyboard: no" do
      refute RootScene.escape_clears_selection?(%State{keyboard_owner: :side_pane})
    end

    for flag <- [
          :show_goto_line,
          :show_search_bar,
          :show_unsaved_prompt,
          :show_file_picker,
          :show_nav_delete_prompt,
          :show_save_settings_prompt,
          :show_project_replace_prompt,
          :show_about,
          :show_shortcuts
        ] do
      test "#{flag} is up: no — that overlay owns Escape" do
        refute RootScene.escape_clears_selection?(%State{unquote(flag) => true})
      end
    end
  end

  # ---------------------------------------------------------------------------
  # The wiring
  # ---------------------------------------------------------------------------

  describe "Escape through handle_input/3" do
    setup do
      {:ok, ref} = Quillex.Buffer.open(%{data: ["Hello World", "second line"]})

      on_exit(fn -> Quillex.Buffer.close(ref, :discard) end)

      {:ok, snapshot} = Quillex.Buffer.dispatch(ref, {:select_range, {1, 1}, {1, 6}})
      assert snapshot.selection == %{start: {1, 1}, end: {1, 6}}

      {:ok, ref: ref}
    end

    defp escape(scene), do: RootScene.handle_input({:key, {:key_esc, 1, []}}, nil, scene)

    defp selection(ref) do
      {:ok, snapshot} = Quillex.Buffer.fetch(ref)
      {snapshot.selection, snapshot.cursor}
    end

    test "clears the selection and leaves the cursor where it is", %{ref: ref} do
      {_sel, cursor_before} = selection(ref)
      scene = scene_with(%{active_buf: ref}, [ref])

      assert {:noreply, _scene} = escape(scene)

      assert {nil, ^cursor_before} = selection(ref)
    end

    test "leaves the selection alone while the project search pane is open", %{ref: ref} do
      scene = scene_with(%{active_buf: ref, show_project_search: true}, [ref])

      assert {:noreply, _scene} = escape(scene)

      assert {%{start: {1, 1}, end: {1, 6}}, _cursor} = selection(ref)
    end

    test "leaves the selection alone while the find bar is open", %{ref: ref} do
      scene = scene_with(%{active_buf: ref, show_search_bar: true}, [ref])

      assert {:noreply, _scene} = escape(scene)

      assert {%{start: {1, 1}, end: {1, 6}}, _cursor} = selection(ref)
    end

    test "with nothing selected it is a harmless no-op", %{ref: ref} do
      scene = scene_with(%{active_buf: ref}, [ref])
      assert {:noreply, _} = escape(scene)
      {nil, cursor} = selection(ref)

      assert {:noreply, _} = escape(scene)
      assert {nil, ^cursor} = selection(ref)
    end

    # The driver emits :key_esc. A clause matching :key_escape could only ever
    # fire from a harness sending the wrong atom, and a test that passed on it
    # would be proving nothing — so the wrong atom must do nothing at all.
    test ":key_escape, the atom no driver sends, does not clear anything", %{ref: ref} do
      scene = scene_with(%{active_buf: ref}, [ref])

      assert {:noreply, _scene} =
               RootScene.handle_input({:key, {:key_escape, 1, []}}, nil, scene)

      assert {%{start: {1, 1}, end: {1, 6}}, _cursor} = selection(ref)
    end
  end
end
