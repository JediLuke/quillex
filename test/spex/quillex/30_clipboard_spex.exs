defmodule Quillex.ClipboardSpex do
  @moduledoc """
  End-to-end clipboard regression coverage.

  Unlike the older integration scenario, these Spex assert that Copy writes
  the selected bytes to the configured clipboard backend and that Paste reads
  those bytes back into the document. Both the keyboard and Edit-menu routes
  are covered. Test configuration uses a file-backed command pair so the test
  remains deterministic and never overwrites the developer's real clipboard.
  """
  use SexySpex

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers

  @clipboard_file "/tmp/quillex_test_clipboard"

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(2_000)
    Quillex.TestHelpers.AppReset.reset_layout!()
    :ok
  end

  defp new_focused_buffer(text) do
    Probes.click_element("icon_menu_file")
    Process.sleep(150)
    Probes.click_element("icon_menu_file_new")
    Process.sleep(350)
    Probes.send_keys("escape", [])
    Probes.send_mouse_click(400, 400)
    Probes.send_text(text)
    Process.sleep(250)
    {:ok, _} = wait_for_content(text)
  end

  defp wait_for_content(expected) do
    with {:ok, viewport} <- Scenic.ViewPort.info(:main_viewport) do
      SemanticHelpers.wait_for_buffer_content(viewport, expected, 5_000)
    end
  end

  defp wait_for_view(predicate, attempts \\ 100)
  defp wait_for_view(_predicate, 0), do: flunk("view snapshot did not update")

  defp wait_for_view(predicate, attempts) do
    view = Quillex.RadixCache.ViewStore.get_state()

    if predicate.(view) do
      view
    else
      Process.sleep(10)
      wait_for_view(predicate, attempts - 1)
    end
  end

  defp select_first_four_characters do
    Probes.send_keys("home", [])

    for _ <- 1..4 do
      Probes.send_keys("right", [:shift])
      Process.sleep(30)
    end

    Process.sleep(100)
  end

  defp choose_edit_item(item) do
    Probes.click_element("icon_menu_edit")
    Process.sleep(150)
    Probes.click_element("icon_menu_edit_#{item}")
    Process.sleep(250)
  end

  defp buffer_pane_graph do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :buffer_pane)
    pane_pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pane_pid).assigns.graph
  end

  spex "Selection highlight shares the cursor row",
    description: "A selected range and insertion cursor have the same vertical origin",
    tags: [:selection, :cursor, :geometry] do
    scenario "selecting text with Shift+Right", _context do
      given_ "a focused buffer with four selected characters", context do
        new_focused_buffer("aligned text")
        select_first_four_characters()
        {:ok, context}
      end

      then_ "the highlight is vertically aligned with the cursor", context do
        graph = buffer_pane_graph()
        [cursor] = Scenic.Graph.get(graph, :cursor)
        [highlight] = Scenic.Graph.get(graph, {:selection_highlight, 1})

        {_cursor_x, cursor_y} = Scenic.Primitive.get_transform(cursor, :translate)
        {_highlight_x, highlight_y} = Scenic.Primitive.get_transform(highlight, :translate)

        assert highlight_y == cursor_y,
               "selection row started at y=#{highlight_y}, cursor started at y=#{cursor_y}"

        {:ok, context}
      end
    end
  end

  spex "Clipboard - keyboard copy and paste",
    description: "Ctrl+C writes selected text and Ctrl+V inserts it",
    tags: [:clipboard, :copy, :paste, :keyboard] do
    scenario "copy the first word and paste it at the end", _context do
      given_ "a focused buffer containing 'copy me'", context do
        File.rm(@clipboard_file)
        new_focused_buffer("copy me")
        select_first_four_characters()
        {:ok, context}
      end

      when_ "Ctrl+C copies 'copy' and Ctrl+V pastes at the end", context do
        Probes.send_keys("c", [:ctrl])
        Process.sleep(200)
        assert File.read!(@clipboard_file) == "copy"

        assert wait_for_view(&(&1.status_message == "Copied 'copy'")).status_message ==
                 "Copied 'copy'"

        Probes.send_keys("end", [])
        Probes.send_keys("v", [:ctrl])
        {:ok, context}
      end

      then_ "the document contains the pasted text", context do
        {:ok, _} = wait_for_content("copy mecopy")
        {:ok, context}
      end
    end
  end

  spex "Clipboard - Edit menu copy and paste",
    description: "Edit → Copy writes selected text and Edit → Paste inserts it",
    tags: [:clipboard, :copy, :paste, :menu] do
    scenario "copy and paste through the dropdown menu", _context do
      given_ "a focused buffer containing 'menu route'", context do
        File.rm(@clipboard_file)
        new_focused_buffer("menu route")
        select_first_four_characters()
        {:ok, context}
      end

      when_ "Edit → Copy copies 'menu' and Edit → Paste pastes at the end", context do
        choose_edit_item("copy")
        assert File.read!(@clipboard_file) == "menu"

        Probes.send_keys("end", [])
        choose_edit_item("paste")
        {:ok, context}
      end

      then_ "the document contains the pasted text", context do
        {:ok, _} = wait_for_content("menu routemenu")
        {:ok, context}
      end
    end
  end

  spex "Clipboard action feedback can be disabled",
    description: "The View toggle suppresses low-level confirmations but not clipboard behavior",
    tags: [:clipboard, :feedback, :view_menu] do
    scenario "copy while Action Feedback is disabled", _context do
      given_ "selected text and Action Feedback switched off through View", context do
        new_focused_buffer("quiet copy")
        select_first_four_characters()

        Probes.click_element("icon_menu_view")
        Process.sleep(150)
        Probes.click_element("icon_menu_view_action_feedback")
        Quillex.RadixCache.ViewStore.sync()
        assert wait_for_view(&(&1.show_action_feedback == false)).show_action_feedback == false

        Quillex.RadixCache.ViewStore.show_status("ordinary status", :warning)
        Quillex.RadixCache.ViewStore.sync()
        {:ok, context}
      end

      when_ "the selection is copied", context do
        Probes.send_keys("c", [:ctrl])
        Process.sleep(200)
        {:ok, context}
      end

      then_ "copy succeeds without replacing the ordinary notification", context do
        assert File.read!(@clipboard_file) == "quie"

        assert wait_for_view(&(&1.status_message == "ordinary status")).status_message ==
                 "ordinary status"

        Probes.click_element("icon_menu_view")
        Process.sleep(150)
        Probes.click_element("icon_menu_view_action_feedback")
        Quillex.RadixCache.ViewStore.sync()
        assert wait_for_view(& &1.show_action_feedback).show_action_feedback
        {:ok, context}
      end
    end
  end

  spex "Undo and redo report applied actions",
    description: "Successful history changes produce low-level confirmations",
    tags: [:feedback, :undo, :redo] do
    scenario "undo and redo through keyboard shortcuts", _context do
      given_ "a focused buffer with an undoable edit", context do
        new_focused_buffer("history")
        Probes.send_text("!")
        Process.sleep(100)
        {:ok, context}
      end

      when_ "the edit is undone", context do
        Probes.send_keys("z", [:ctrl])
        {:ok, context}
      end

      then_ "the notification confirms undo and redo", context do
        assert wait_for_view(&(&1.status_message == "Applied undo")).status_message ==
                 "Applied undo"

        Probes.send_keys("z", [:ctrl, :shift])

        assert wait_for_view(&(&1.status_message == "Applied redo")).status_message ==
                 "Applied redo"

        {:ok, context}
      end
    end
  end
end
