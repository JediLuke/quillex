defmodule Quillex.DiscoverabilitySpex do
  @moduledoc """
  Part II item 8: *"otherwise how will users know it exists"*.

  The audit made durable. Every keyboard binding Quillex implements is listed
  here with the way a user is expected to find it — a menu row, a line in
  Help → Keyboard Shortcuts, or both. A binding that appears in neither is
  invisible: discoverable only by guessing, or by reading the source.

  The list is deliberately written out rather than derived from the registry,
  because deriving it from the very thing under test would assert nothing. Each
  entry was checked against the code that handles the key.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset
  alias Quillex.Commands

  # {shortcut, where the key is handled}. The right-hand column is the audit
  # trail: it is the answer to "does this binding really exist?".
  @bindings [
    {"Ctrl+N", "RootScene menu/keyboard — new buffer"},
    {"Ctrl+O", "RootScene — file picker"},
    {"Ctrl+S", "TextField input_to_buffer_action, key_s"},
    {"Ctrl+Shift+S", "RootScene — save as"},
    {"Ctrl+W", "RootScene handle_input, key_w"},
    {"Ctrl+Z", "TextField input_to_buffer_action, key_z"},
    {"Ctrl+Shift+Z", "TextField input_to_buffer_action, key_z with shift"},
    {"Ctrl+X", "TextField input_to_buffer_action, key_x"},
    {"Ctrl+C", "TextField input_to_buffer_action, key_c"},
    {"Ctrl+V", "TextField input_to_buffer_action, key_v"},
    {"Ctrl+A", "TextField input_to_buffer_action, key_a"},
    {"Ctrl+D", "RootScene handle_input, key_d with ctrl"},
    {"Ctrl+Backspace", "TextField input_to_buffer_action, key_backspace with ctrl"},
    {"Ctrl+Delete", "TextField input_to_buffer_action, key_delete with ctrl"},
    {"Tab", "TextField input_to_buffer_action, key_tab"},
    {"Shift+Tab", "TextField input_to_buffer_action, key_tab with shift"},
    {"Ctrl+F", "TextField input_to_buffer_action, key_f"},
    {"Ctrl+H", "TextField input_to_buffer_action, key_h"},
    {"Ctrl+Shift+F", "RootScene handle_input, key_f with shift"},
    {"Ctrl+Shift+H", "RootScene handle_input, key_h with shift"},
    {"F3", "TextField input_to_buffer_action, key_f3"},
    {"Ctrl+G", "TextField input_to_buffer_action, key_g"},
    {"Ctrl+Left", "TextField input_to_buffer_action, key_left with ctrl"},
    {"Ctrl+Right", "TextField input_to_buffer_action, key_right with ctrl"},
    {"Home", "TextField input_to_buffer_action, key_home"},
    {"End", "TextField input_to_buffer_action, key_end"},
    {"Ctrl+Home", "RootScene handle_input, key_home with ctrl"},
    {"Ctrl+End", "RootScene handle_input, key_end with ctrl"},
    {"PageUp", "RootScene handle_input, key_pageup"},
    {"PageDown", "RootScene handle_input, key_pagedown"},
    {"Shift+Move", "TextField arrows/Home/End with shift; RootScene Ctrl+Shift+Home/End"},
    {"Ctrl+Alt+[", "RootScene — toggle fold"},
    {"Ctrl+Alt+]", "RootScene — unfold all"},
    {"Ctrl++", "RootScene handle_input, key_equal with ctrl"},
    {"Ctrl+-", "RootScene handle_input, key_minus with ctrl"},
    {"Ctrl+0", "RootScene handle_input, key_0 with ctrl"},
    {"Escape", "RootScene / SearchBar / dialogs"}
  ]

  defp root_state, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

  defp child_state(id) do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, id)
    :sys.get_state(pid, 30_000).assigns.state
  end

  defp menu_row_ids do
    child_state(:icon_menu).menus
    |> Enum.flat_map(fn menu ->
      Enum.map(menu.items, &ScenicWidgets.IconMenu.State.get_item_id/1)
    end)
  end

  defp wait_until(predicate, timeout \\ 3_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait(predicate, deadline)
  end

  defp do_wait(predicate, deadline) do
    cond do
      predicate.() -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true -> Process.sleep(25) && do_wait(predicate, deadline)
    end
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()
    Process.sleep(300)
    :ok
  end

  spex "Every shortcut the editor implements is written down somewhere",
    description: "A binding in no menu and no reference is discoverable only by guessing",
    tags: [:phase_47, :discoverability] do
    scenario "auditing the bindings against the registry" do
      then_ "each one is registered", context do
        registered = Commands.all() |> Enum.map(& &1.shortcut) |> MapSet.new()

        missing =
          @bindings
          |> Enum.reject(fn {shortcut, _where} -> MapSet.member?(registered, shortcut) end)

        assert missing == [],
               "these bindings exist but are in no menu and no reference: #{inspect(missing)}"

        {:ok, context}
      end

      then_ "and each one reaches the Keyboard Shortcuts reference", context do
        lines = Commands.shortcut_lines()

        for {shortcut, _where} <- @bindings do
          assert Enum.any?(lines, &String.contains?(&1, shortcut)),
                 "#{shortcut} never reaches Help → Keyboard Shortcuts"
        end

        {:ok, context}
      end

      then_ "the reference is grouped, so it can be read rather than scanned", context do
        lines = Commands.shortcut_lines()

        for section <- Commands.sections() do
          assert section in lines, "the reference has no #{inspect(section)} section"
        end

        # Headings are flush left, entries indented under them.
        for line <- lines, line not in Commands.sections() do
          assert String.starts_with?(line, "  "), "#{inspect(line)} is not under a heading"
        end

        {:ok, context}
      end

      then_ "no registered command is missing from the menu it claims", context do
        rows = menu_row_ids()

        for command <- Commands.all(), command.menu != nil do
          assert Atom.to_string(command.id) in rows,
                 "#{command.id} says it lives in the #{command.menu} menu but has no row there"
        end

        {:ok, context}
      end
    end
  end

  spex "Select All is reachable with the mouse",
    description: "The one clipboard-adjacent command that had no menu row now has one",
    tags: [:phase_47, :discoverability] do
    scenario "choosing Edit → Select All" do
      given_ "a buffer with some text", context do
        {:ok, buf} =
          Quillex.Buffer.new(%{name: "discover.txt", data: ["alpha", "beta", "gamma"]})

        :ok = Quillex.Buffer.activate(buf)
        Process.sleep(400)
        Probes.click(800, 300)
        Process.sleep(150)
        {:ok, Map.put(context, :buf, buf)}
      end

      when_ "Edit → Select All is chosen", context do
        Probes.click_element("icon_menu_edit")
        Process.sleep(250)
        Probes.click_element("icon_menu_edit_select_all")
        Process.sleep(350)
        {:ok, context}
      end

      then_ "the whole buffer is selected", context do
        assert wait_until(fn ->
                 {:ok, snapshot} = Quillex.Buffer.fetch(context.buf)
                 snapshot.selection != nil
               end),
               "Edit → Select All did not select anything"

        {:ok, snapshot} = Quillex.Buffer.fetch(context.buf)
        assert snapshot.selection.start == {1, 1}
        assert snapshot.selection.end == {3, 6}
        {:ok, context}
      end
    end
  end

  spex "The Keyboard Shortcuts window fits on screen",
    description: "A reference you cannot read the bottom of is not a reference",
    tags: [:phase_47, :discoverability] do
    scenario "opening Help → Keyboard Shortcuts" do
      when_ "the shortcuts dialog is opened", context do
        Probes.click_element("icon_menu_help")
        Process.sleep(250)
        Probes.click_element("icon_menu_help_shortcuts")
        Process.sleep(500)
        assert wait_until(fn -> root_state().show_shortcuts end)
        {:ok, context}
      end

      then_ "its panel is inside the window", context do
        %{y: y, height: height, columns: columns} = panel_bounds()
        window_height = root_state().frame.size.height

        assert columns >= 2,
               "the reference is short enough to be one column now; if that is " <>
                 "deliberate, relax this — it is here because the list outgrew the window"


        assert y >= 0 and y + height <= window_height,
               "the shortcuts panel runs from #{trunc(y)} to #{trunc(y + height)} in a " <>
                 "#{trunc(window_height)}px window"

        Probes.take_screenshot("47_keyboard_shortcuts")
        Probes.send_keys("escape", [])
        Process.sleep(300)
        {:ok, context}
      end
    end
  end

  # The widget's own layout, not the test's arithmetic about it.
  defp panel_bounds do
    ScenicWidgets.PopupModal.panel_bounds(child_state(:shortcuts_dialog))
  end
end
