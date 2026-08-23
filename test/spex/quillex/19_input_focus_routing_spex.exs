defmodule Quillex.InputFocusRoutingSpex do
  @moduledoc """
  Phase 19: Input Focus Routing (Roadmap 1.0, Phase 1 regression coverage)

  Guards against the two double-delivery bugs found in the 2026-07-31 manual
  QA pass:

  1. With the file nav open, pressing Enter in the editor both inserted a
     newline AND activated the nav's focused item (opening a file / new
     buffer). Root cause: SideNav requested [:key] globally with no focus
     gate — fixed by gating all SideNav key handlers on component focus.

  2. Scrolling over the file nav also scrolled the text pane. Root cause:
     TextField processed :cursor_scroll regardless of pointer position —
     fixed by bound-checking scroll coordinates against the TextField frame.

  Both scenarios FAIL on the pre-fix code by construction: scenario 1 types
  after pressing Enter and asserts the earlier text is still on screen
  (a buffer switch would hide it); scenario 2 asserts the top-of-file text
  is still on screen after aggressive scrolling over the nav.
  """
  use SexySpex

  alias ScenicMcp.Probes
  alias ScenicMcp.Query

  # Test window is 2000x1200 (see Quillex.App.window_size/0 for :test).
  # The file nav occupies the left 250px below the 35px top bar.
  @nav_point {125, 500}
  @buffer_point {900, 600}

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(2000)

    # Start from a known-clean editor rather than inheriting whatever
    # the previous spex file left behind (buffers, open nav, scroll).
    Quillex.TestHelpers.AppReset.reset!()

    :ok
  end

  # Open the View menu, then click the file-nav toggle (same helper as spex 10).
  defp toggle_file_nav do
    Probes.click_element("icon_menu_view")
    Process.sleep(200)
    Probes.click_element("icon_menu_view_file_nav")
    Process.sleep(500)
  end

  defp file_nav_visible? do
    case Process.whereis(Quillex.RootScene) do
      nil ->
        false

      pid ->
        root = :sys.get_state(pid)

        case Scenic.Scene.child(root, :file_nav) do
          {:ok, children} when is_list(children) -> Enum.any?(children, &Process.alive?/1)
          {:ok, child} when is_pid(child) -> Process.alive?(child)
          _ -> false
        end
    end
  end

  defp ensure_file_nav_visible do
    unless file_nav_visible?(), do: toggle_file_nav()
    assert file_nav_visible?(), "file navigator did not become a live component"
  end

  defp ensure_file_nav_hidden do
    if file_nav_visible?(), do: toggle_file_nav()
  end

  defp buffer_pane_pid do
    root = :sys.get_state(Process.whereis(Quillex.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :buffer_pane)
    if is_list(child), do: List.first(child), else: child
  end

  defp buffer_pane_state, do: :sys.get_state(buffer_pane_pid()).assigns.state

  defp file_nav_state do
    root = :sys.get_state(Process.whereis(Quillex.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :file_nav)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid).assigns.state
  end

  defp click_nav_path(path) do
    state = file_nav_state()
    %{y: row_y, height: row_h} = Map.fetch!(state.item_bounds, path)
    x = state.frame.pin.x + 40
    y = state.frame.pin.y + row_y + row_h / 2 - state.scroll.offset_y
    Probes.click(trunc(x), trunc(y))
    Process.sleep(400)
  end

  defp file_picker_state do
    root = :sys.get_state(Process.whereis(Quillex.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :file_picker)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid).assigns.state
  end

  defp open_picker_entry(name) do
    state = file_picker_state()
    index = Enum.find_index(state.entries, &(&1.name == name))
    refute is_nil(index), "#{name} was not visible in #{state.current_path}"

    {fw, fh} = state.frame.size.box
    modal_x = fw * 0.15
    modal_y = fh * 0.15
    x = trunc(modal_x + 50)
    y = trunc(modal_y + 92 + index * ScenicWidgets.FilePicker.State.item_height() + 15)

    Probes.click(x, y)
    Process.sleep(80)
    Probes.click(x, y)
    Process.sleep(350)
  end

  defp wait_for_buffer_switch(previous_id, attempts \\ 100)

  defp wait_for_buffer_switch(_previous_id, 0),
    do: flunk("buffer pane did not receive the newly opened file")

  defp wait_for_buffer_switch(previous_id, attempts) do
    state = buffer_pane_state()

    if state.buffer_id != previous_id do
      state
    else
      Process.sleep(20)
      wait_for_buffer_switch(previous_id, attempts - 1)
    end
  end

  spex "Keyboard focus is exclusive between editor and file nav",
    description:
      "Enter (and other keys) typed into the editor must not activate items in the file nav sidebar",
    tags: [:phase_19, :focus, :input_routing] do
    scenario "Enter in the editor inserts a newline and nothing else" do
      given_ "the file nav is open and the editor has focus with text typed", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)
        ensure_file_nav_visible()
        assert file_nav_visible?()

        # Click into the buffer area to give the editor focus
        {bx, by} = @buffer_point
        Probes.click(bx, by)
        Process.sleep(200)

        Probes.send_text("alpha")
        Process.sleep(300)
        assert Query.text_visible?("alpha")
        {:ok, context}
      end

      when_ "the user presses Down then Enter, then keeps typing", context do
        # Pre-fix, Down moved the nav's item focus and Enter activated it
        # (opening a file in a new buffer, hiding this buffer's content).
        Probes.send_keys("down", [])
        Process.sleep(150)
        Probes.send_keys("enter", [])
        Process.sleep(300)
        Probes.send_text("beta")
        Process.sleep(300)
        {:ok, context}
      end

      then_ "both texts are on screen — same buffer, newline honoured", context do
        assert Query.text_visible?("alpha"),
               "text typed before Enter vanished — Enter switched buffers (nav received the key)"

        assert Query.text_visible?("beta"),
               "text typed after Enter is not visible — focus was lost to the file nav"

        Quillex.TestHelpers.Invariants.assert_invariants!()
        {:ok, context}
      end
    end
  end

  spex "Scroll is positional between editor and file nav",
    description: "Scrolling with the pointer over the file nav must not scroll the text pane",
    tags: [:phase_19, :scroll, :input_routing] do
    scenario "Wheel events over the nav leave the editor viewport untouched" do
      given_ "a tall document is open with its first line visible, nav open", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)

        :ok =
          Quillex.TestHelpers.FileOpener.open_file(Path.expand("biblio/spinozas_ethics_p1.txt"))

        Process.sleep(800)
        ensure_file_nav_visible()

        # A document opened earlier in this VM comes back at its remembered
        # viewport (buffer-view restore); this scenario needs the top.
        Probes.send_keys("home", [:ctrl])
        Process.sleep(300)

        # ScriptInspector = actually-drawn text; the semantic table holds the
        # whole document regardless of scroll and cannot detect scrolling.
        assert Quillex.TestHelpers.ScriptInspector.rendered_text_contains?("CONCERNING GOD"),
               "expected the top of the Ethics to be on screen after opening it"

        {:ok, context}
      end

      when_ "the user scrolls aggressively with the pointer over the file nav", context do
        {nx, ny} = @nav_point

        for _ <- 1..10 do
          Probes.send_scroll(0, -5, nx, ny)
          Process.sleep(50)
        end

        Process.sleep(300)
        {:ok, context}
      end

      then_ "the editor still shows the first line of the file", context do
        assert Quillex.TestHelpers.ScriptInspector.rendered_text_contains?("CONCERNING GOD"),
               "the text pane scrolled even though the pointer was over the file nav"

        Quillex.TestHelpers.Invariants.assert_invariants!()
        {:ok, context}
      end
    end

    scenario "Cleanup: close the file nav for subsequent spex" do
      given_ "the file nav is open", context do
        {:ok, context}
      end

      when_ "we toggle it off", context do
        ensure_file_nav_hidden()
        {:ok, context}
      end

      then_ "the project tree is no longer rendered", context do
        refute file_nav_visible?()
        Quillex.TestHelpers.Invariants.assert_invariants!()
        {:ok, context}
      end
    end
  end

  spex "A newly opened file scrolls without activation",
    description:
      "The wheel works over the editor immediately after a buffer switch, without a click",
    tags: [:scroll, :buffer_switch, :focus] do
    scenario "wheel immediately after opening a tall file", _context do
      given_ "the navigator owns focus before a tall file is opened", context do
        ensure_file_nav_visible()

        :ok = Quillex.TestHelpers.FileOpener.open_file(Path.expand("mix.exs"))
        Process.sleep(300)

        root = :sys.get_state(Process.whereis(Quillex.RootScene))
        Scenic.Scene.put_child(root, :buffer_pane, :blur)
        Scenic.Scene.put_child(root, :file_nav, :focus)
        Process.sleep(100)

        previous_id = buffer_pane_state().buffer_id

        :ok =
          Quillex.TestHelpers.FileOpener.open_file(Path.expand("biblio/spinozas_ethics_p1.txt"))

        _state = wait_for_buffer_switch(previous_id)

        # File-open/reload notifications alter the pane's available height.
        # That chrome transition must resize the live component, not delete it
        # during the exact moment the user's first wheel event can arrive.
        pane_pid = buffer_pane_pid()
        Quillex.RadixCache.ViewStore.show_status("Opened file", :info)
        Quillex.RadixCache.ViewStore.sync()
        Process.sleep(50)
        assert buffer_pane_pid() == pane_pid

        pane_state = buffer_pane_state()

        {:ok,
         context
         |> Map.put(:frame, pane_state.frame)
         |> Map.put(:before_offset, pane_state.scroll.offset_y)}
      end

      when_ "the wheel moves over the text pane without clicking it first", context do
        frame = context.frame
        # Exercise the pane's left edge. Scenic transforms this to local x=10;
        # the old bug compared that against the parent-space frame.pin.x and
        # silently rejected the wheel until a click moved focus.
        x = frame.pin.x + 10
        y = frame.pin.y + trunc(frame.size.height * 0.5)
        Probes.send_mouse_move(x, y)
        dy = if context.before_offset > 0, do: 5, else: -5
        Probes.send_scroll(0, dy, x, y)
        Process.sleep(250)
        {:ok, context}
      end

      then_ "the document viewport has moved", context do
        assert buffer_pane_state().scroll.offset_y != context.before_offset,
               "wheel input was ignored until the TextField was clicked"

        :ok = Quillex.TestHelpers.FileOpener.open_file(Path.expand("mix.exs"))
        Process.sleep(250)
        ensure_file_nav_hidden()
        {:ok, context}
      end
    end
  end

  spex "A file opened through the real picker scrolls immediately",
    description:
      "File → Open → choose a tall file releases the modal and the first wheel gesture reaches the editor",
    tags: [:scroll, :file_picker, :focus, :regression] do
    scenario "wheel immediately after the picker opens a tall file", _context do
      given_ "the Open File dialog is driven through the menubar", context do
        ensure_file_nav_hidden()

        :ok = Quillex.TestHelpers.FileOpener.open_file(Path.expand("mix.exs"))
        Process.sleep(300)
        previous_id = buffer_pane_state().buffer_id

        Probes.click_element("icon_menu_file")
        Process.sleep(200)
        Probes.click_element("icon_menu_file_open")
        Process.sleep(400)

        assert file_picker_state().current_path == File.cwd!()
        open_picker_entry("biblio")
        assert Path.basename(file_picker_state().current_path) == "biblio"
        open_picker_entry("spinozas_ethics_p1.txt")

        state = wait_for_buffer_switch(previous_id)
        refute state.overlay_open, "closing FilePicker must remove the editor overlay gate"

        {:ok,
         context
         |> Map.put(:frame, state.frame)
         |> Map.put(:before_offset, state.scroll.offset_y)}
      end

      when_ "the first wheel gesture lands on the newly opened document", context do
        frame = context.frame
        x = frame.pin.x + 20
        y = frame.pin.y + trunc(frame.size.height * 0.5)
        Probes.send_mouse_move(x, y)
        dy = if context.before_offset > 0, do: 5, else: -5
        Probes.send_scroll(0, dy, x, y)
        Process.sleep(250)
        {:ok, context}
      end

      then_ "the document scrolls without an activation click", context do
        assert buffer_pane_state().scroll.offset_y != context.before_offset,
               "the picker closed but the first editor wheel gesture was lost"

        {:ok, context}
      end
    end
  end

  spex "A buffer opened from the navigator scrolls immediately",
    description:
      "Clicking a file in the project tree cannot leave the navigator or an old pane blocking editor wheel input",
    tags: [:scroll, :file_nav, :focus, :regression] do
    scenario "wheel immediately after clicking a tall file in the tree", _context do
      given_ "the file is opened by clicking the actual navigator rows", context do
        :ok = Quillex.TestHelpers.FileOpener.open_file(Path.expand("mix.exs"))
        Process.sleep(300)
        ensure_file_nav_visible()
        root = File.cwd!()
        biblio = Path.join(root, "biblio")
        file = Path.join(biblio, "spinozas_ethics_p1.txt")

        unless Map.has_key?(file_nav_state().item_bounds, file) do
          click_nav_path(biblio)
        end

        root_scene = :sys.get_state(Process.whereis(Quillex.RootScene))
        Scenic.Scene.put_child(root_scene, :buffer_pane, {:set_overlay_open, true})
        Process.sleep(100)
        assert buffer_pane_state().overlay_open

        previous_id = buffer_pane_state().buffer_id
        click_nav_path(file)
        state = wait_for_buffer_switch(previous_id)
        refute state.overlay_open, "opening from the navigator must clear stale overlay gates"

        {:ok,
         context
         |> Map.put(:frame, state.frame)
         |> Map.put(:before_offset, state.scroll.offset_y)}
      end

      when_ "the pointer moves over the editor and the wheel turns", context do
        frame = context.frame
        x = frame.pin.x + trunc(frame.size.width * 0.5)
        y = frame.pin.y + trunc(frame.size.height * 0.5)
        Probes.send_mouse_move(x, y)
        dy = if context.before_offset > 0, do: 5, else: -5
        Probes.send_scroll(0, dy, x, y)
        Process.sleep(250)
        {:ok, context}
      end

      then_ "the opened buffer scrolls on that first gesture", context do
        assert buffer_pane_state().scroll.offset_y != context.before_offset,
               "opening from the navigator left editor wheel input blocked"

        ensure_file_nav_hidden()
        {:ok, context}
      end
    end
  end
end
