defmodule Quillex.CommandKeySpex do
  @moduledoc """
  Which key means "command", and everything that follows from saying so.

  On Linux it is Control. On macOS it is Command, which Scenic reports as
  `:meta` — and a Mac user pressing Control expects nothing to happen. The
  setting exists because muscle memory belongs to the person: someone who has
  remapped their keyboard, or who moved from one platform to the other, should
  be able to say so once.

  The failure this is really guarding against is the two halves drifting: what
  the menus PRINT and what the key handling ANSWERS TO come from one setting,
  and if they ever came from two, the editor would advertise a shortcut it does
  not have. So this checks the drawn text and a real keystroke, not the state.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.RadixCache.ViewStore
  alias Quillex.TestHelpers.AppReset
  import Quillex.TestHelpers.Integration

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()
    Process.sleep(300)

    on_exit(fn -> ViewStore.set_primary_modifier(:ctrl) end)
    :ok
  end

  defp root_state, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

  # What a menu row will actually say — read from the built menus rather than
  # the registry, because the registry stores "Mod+S" and the whole question
  # is what that turns into on the way to the screen.
  defp menu_shortcut(menu_id, row_id) do
    root_state()
    |> QuillEx.RootScene.Renderizer.build_menus()
    |> Enum.find(&(&1.id == menu_id))
    |> Map.fetch!(:items)
    |> List.flatten()
    |> Enum.find(&(Map.get(&1, :id) == row_id))
    |> Map.fetch!(:shortcut)
  end

  defp set_modifier(modifier) do
    ViewStore.set_primary_modifier(modifier)
    ViewStore.sync()
    assert wait_until(fn -> root_state().primary_modifier == modifier end)
    # The menus are rebuilt off the mirrored state, which arrives by broadcast.
    Process.sleep(600)
  end

  spex "The command key is a setting, and every shortcut follows it",
    description: "Ctrl on Linux, ⌘ on a Mac, and the menus say whichever it is",
    tags: [:phase_53, :shortcuts, :menubar] do
    scenario "switching the keyboard the editor thinks it has" do
      given_ "an editor set up for a Control keyboard", context do
        # The buffer is prepared BEFORE the switch: fresh_editor! resets the
        # display settings, the command key among them, so preparing it later
        # would quietly undo the very thing under test.
        fresh_editor!()
        ensure_editor_focused()
        Process.sleep(300)
        Probes.send_text("hello")
        Process.sleep(400)

        set_modifier(:ctrl)

        assert menu_shortcut(:file, "save") == "Ctrl+S"
        assert menu_shortcut(:file, "save_as") == "Ctrl+Shift+S"
        {:ok, context}
      end

      when_ "the person says this is a Mac", context do
        set_modifier(:meta)
        {:ok, context}
      end

      then_ "every menu re-letters itself in Mac spelling", context do
        # Mac names, in the order a Mac menu prints them — Shift before Cmd,
        # never the reverse. Words rather than ⇧⌘ because the menu font has no
        # glyph for those and Scenic draws a missing glyph as an empty box;
        # see Quillex.Shortcuts.
        assert menu_shortcut(:file, "save") == "Cmd+S"
        assert menu_shortcut(:file, "save_as") == "Shift+Cmd+S"
        assert menu_shortcut(:edit, "undo") == "Cmd+Z"
        assert menu_shortcut(:edit, "redo") == "Shift+Cmd+Z"

        {:ok, context}
      end

      then_ "and the shortcut reference agrees with the menus", context do
        reference = Quillex.Commands.shortcut_lines() |> Enum.join("\\n")

        assert String.contains?(reference, "Cmd+S"),
               "Help → Keyboard Shortcuts is still printing the other platform's keys"

        refute String.contains?(reference, "Ctrl+"),
               "a Ctrl+ left in the reference is a shortcut this editor does not have"

        {:ok, context}
      end

      then_ "the keys themselves follow: Command selects all, and Control does not", context do
        # The half that would be invisible from state, and the one that
        # matters: a menu can say Cmd+A all it likes, but if Ctrl+A still selects
        # all then the shortcut fires on two different keys and the setting is
        # decoration.
        Probes.send_keys("a", [:ctrl])
        Process.sleep(300)
        Probes.send_text("X")
        Process.sleep(400)

        assert active_buffer_text() == "helloX",
               "Control is not the command key here, so Ctrl+A must not select all — " <>
                 "got #{inspect(active_buffer_text())}"

        Probes.send_keys("a", [:meta])
        Process.sleep(300)
        Probes.send_text("Y")
        Process.sleep(400)

        assert active_buffer_text() == "Y",
               "Command+A should select all so the next keystroke replaces it — " <>
                 "got #{inspect(active_buffer_text())}"

        {:ok, context}
      end

      then_ "and switching back restores Control spelling everywhere", context do
        set_modifier(:ctrl)

        assert menu_shortcut(:file, "save") == "Ctrl+S"
        assert Quillex.Commands.shortcut_lines() |> Enum.join("\\n") |> String.contains?("Ctrl+S")

        {:ok, context}
      end

      then_ "and it is a setting that can be saved with the rest", context do
        assert :primary_modifier in Quillex.SettingsFile.persisted_keys()
        {:ok, context}
      end
    end
  end

  defp active_buffer_text do
    {:ok, snapshot} = Quillex.Buffer.fetch(root_state().active_buf)
    Enum.join(snapshot.lines, "\\n")
  end

  defp wait_until(fun, timeout \\ 3_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    Stream.repeatedly(fn ->
      result = fun.()
      unless result, do: Process.sleep(50)
      result
    end)
    |> Enum.find(fn result ->
      result or System.monotonic_time(:millisecond) > deadline
    end)
  end
end
