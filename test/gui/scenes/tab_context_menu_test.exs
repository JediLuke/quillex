defmodule Quillex.RootScene.TabContextMenuTest do
  use ExUnit.Case, async: true

  @moduledoc """
  The pure seams of the tab context menu (right-click a tab → bulk close).

  Everything here is a decision the menu makes before it touches a store:
  which tabs an action targets, which of those need confirming, whether the
  batch would empty the editor, and which row a click landed on. The wiring
  around them — capture/release, the single "Unsaved Changes" prompt, the
  actual closes — is exercised in `test/spex/quillex/69_tab_context_menu_spex.exs`.

  Same pattern as `Quillex.RootScene.UnsavedPromptTest` around `decide_close/2`:
  the functions are public purely so tests can pin them.
  """

  alias Quillex.RootScene
  alias Quillex.RootScene.State, as: RootState
  alias Quillex.Buffer.Ref

  defp buf(name, opts \\ []) do
    %Ref{
      uuid: "uuid-" <> name,
      name: name,
      dirty?: Keyword.get(opts, :dirty?, false),
      external_change: Keyword.get(opts, :external_change)
    }
  end

  defp names(refs), do: Enum.map(refs, & &1.name)

  defp open_menu_state(pos) do
    %RootState{tab_context_menu: %{uuid: "uuid-b", pos: pos}}
  end

  # ---------------------------------------------------------------------------
  # tab_context_targets/3 — which tabs each action closes
  # ---------------------------------------------------------------------------

  describe "tab_context_targets/3" do
    setup do
      {:ok, buffers: [buf("a"), buf("b"), buf("c"), buf("d")]}
    end

    test ":close_others takes everything but the clicked tab, in tab order", %{buffers: buffers} do
      targets = RootScene.tab_context_targets(buffers, "uuid-b", :close_others)
      assert names(targets) == ["a", "c", "d"]
    end

    test ":close_others on the only open tab targets nothing" do
      assert RootScene.tab_context_targets([buf("a")], "uuid-a", :close_others) == []
    end

    test ":close_right takes only the tabs after the clicked one", %{buffers: buffers} do
      targets = RootScene.tab_context_targets(buffers, "uuid-b", :close_right)
      assert names(targets) == ["c", "d"]
    end

    test ":close_right on the first tab takes all the rest", %{buffers: buffers} do
      targets = RootScene.tab_context_targets(buffers, "uuid-a", :close_right)
      assert names(targets) == ["b", "c", "d"]
    end

    test ":close_right on the last tab targets nothing", %{buffers: buffers} do
      assert RootScene.tab_context_targets(buffers, "uuid-d", :close_right) == []
    end

    # "To the right" is a claim about the tab STRIP, and tabs can be dragged
    # into a new order. The buffer list is kept in tab order by BufferManager's
    # reorder, so passing it through is what makes this right — a version that
    # sorted by uuid or open time would silently close the wrong tabs after a
    # drag.
    test ":close_right follows the list order it is given, not the original order" do
      reordered = [buf("d"), buf("c"), buf("b"), buf("a")]
      targets = RootScene.tab_context_targets(reordered, "uuid-c", :close_right)
      assert names(targets) == ["b", "a"]
    end

    test ":close_all takes every tab, clicked one included", %{buffers: buffers} do
      assert RootScene.tab_context_targets(buffers, "uuid-b", :close_all) == buffers
    end
  end

  # ---------------------------------------------------------------------------
  # tab_context_unsaved/1 — which of the targets need confirming
  # ---------------------------------------------------------------------------

  describe "tab_context_unsaved/1" do
    test "keeps the dirty targets, in order, and drops the clean ones" do
      targets = [buf("a"), buf("b", dirty?: true), buf("c"), buf("d", dirty?: true)]
      assert names(RootScene.tab_context_unsaved(targets)) == ["b", "d"]
    end

    test "an all-clean batch needs no confirmation at all" do
      assert RootScene.tab_context_unsaved([buf("a"), buf("b")]) == []
    end

    test "an empty batch needs no confirmation" do
      assert RootScene.tab_context_unsaved([]) == []
    end

    # Deliberate: this is the same test decide_close/2 applies to a single
    # close. A clean buffer whose file was deleted on disk is arguably unsaved
    # too, but changing that is a change to the app's close policy and belongs
    # on the branch making it everywhere — not here, where it would make a
    # bulk close and a Ctrl+W disagree.
    test "a clean buffer is clean even when its file was deleted on disk" do
      assert RootScene.tab_context_unsaved([buf("a", external_change: :deleted)]) == []
    end
  end

  # ---------------------------------------------------------------------------
  # tab_context_needs_fresh_buffer?/2 — does the batch empty the editor
  # ---------------------------------------------------------------------------

  describe "tab_context_needs_fresh_buffer?/2" do
    test "a batch that takes every tab needs a fresh buffer first" do
      buffers = [buf("a"), buf("b")]
      assert RootScene.tab_context_needs_fresh_buffer?(buffers, buffers)
    end

    test "a batch that leaves a tab behind does not" do
      buffers = [buf("a"), buf("b"), buf("c")]
      refute RootScene.tab_context_needs_fresh_buffer?(buffers, [buf("b"), buf("c")])
    end

    test "the single-tab case still counts as emptying the editor" do
      buffers = [buf("a")]
      assert RootScene.tab_context_needs_fresh_buffer?(buffers, buffers)
    end
  end

  # ---------------------------------------------------------------------------
  # tab_context_menu_hit/2 — which row a click landed on
  # ---------------------------------------------------------------------------
  #
  # The popup is scene-owned primitives, so the click is hit-tested by this
  # arithmetic and not by Scenic. Coordinates are viewport-global: the popup
  # group is translated by state.tab_context_menu.pos in the root graph, and
  # the captured press arrives in root coordinates.

  describe "tab_context_menu_hit/2" do
    @pad 6
    @row 28

    setup do
      {w, h} = RootScene.tab_context_menu_size()
      {:ok, state: open_menu_state({100, 40}), w: w, h: h}
    end

    test "the three rows map to the three actions, top to bottom", %{state: state} do
      mid = fn i -> {150, 40 + @pad + i * @row + div(@row, 2)} end

      assert RootScene.tab_context_menu_hit(state, mid.(0)) == :close_others
      assert RootScene.tab_context_menu_hit(state, mid.(1)) == :close_right
      assert RootScene.tab_context_menu_hit(state, mid.(2)) == :close_all
    end

    # Midpoints are forgiving; the boundaries are where a slip sends a click to
    # the WRONG destructive action — "Close Tabs to the Right" landing on
    # "Close All Tabs" is the whole risk of this menu.
    test "each row owns its full band, right up to the boundary", %{state: state, h: h} do
      at = fn dy -> RootScene.tab_context_menu_hit(state, {150, 40 + dy}) end

      assert at.(@pad) == :close_others
      assert at.(@pad + @row - 1) == :close_others
      assert at.(@pad + @row) == :close_right
      assert at.(@pad + 2 * @row - 1) == :close_right
      assert at.(@pad + 2 * @row) == :close_all
      assert at.(h - @pad - 1) == :close_all
    end

    test "the padding strips are inert — nil, not a row and not a dismiss", %{
      state: state,
      h: h
    } do
      assert RootScene.tab_context_menu_hit(state, {150, 40 + 1}) == nil
      assert RootScene.tab_context_menu_hit(state, {150, 40 + h - 1}) == nil
    end

    test "a click outside the popup dismisses it", %{state: state, w: w, h: h} do
      assert RootScene.tab_context_menu_hit(state, {99, 60}) == :outside
      assert RootScene.tab_context_menu_hit(state, {100 + w + 1, 60}) == :outside
      assert RootScene.tab_context_menu_hit(state, {150, 39}) == :outside
      assert RootScene.tab_context_menu_hit(state, {150, 40 + h + 1}) == :outside
    end

    # A click just inside the right edge is on the menu, not outside it —
    # getting this backwards makes the menu vanish when a user clicks the end
    # of a long label.
    test "a click just inside the right edge still lands on its row", %{state: state, w: w} do
      row_y = 40 + @pad + div(@row, 2)
      assert RootScene.tab_context_menu_hit(state, {100 + w - 1, row_y}) == :close_others
    end

    test "the hit test moves with the popup", %{state: _state} do
      moved = open_menu_state({400, 300})
      row_y = 300 + @pad + div(@row, 2)

      assert RootScene.tab_context_menu_hit(moved, {450, row_y}) == :close_others
      assert RootScene.tab_context_menu_hit(moved, {150, row_y}) == :outside
    end
  end

  # ---------------------------------------------------------------------------
  # State defaults
  # ---------------------------------------------------------------------------

  describe "RootScene.State" do
    test "starts with the menu closed and no batch queued" do
      state = %RootState{}
      assert state.tab_context_menu == nil
      assert state.pending_tab_context_close == []
    end
  end
end
