defmodule Quillex.KeyboardOwnershipSpex do
  @moduledoc """
  Exactly one pane owns the keyboard.

  Clicks are positional: they arrive at whichever component sits under the
  pointer, and never at the root scene. So a component that focuses itself on
  click has to SAY so, or the scene cannot take the keyboard off the pane that
  had it. Before it did, the buffer pane and the project search pane could both
  be focused at once, and every keystroke went into the document AND the query
  field — visible as a search query slowly accumulating whatever was typed.
  """
  use SexySpex

  alias ScenicMcp.Probes
  import Quillex.TestHelpers.Integration

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
    end

    Process.sleep(1_500)
    Quillex.TestHelpers.AppReset.reset!()
    Process.sleep(500)
    :ok
  end

  defp root_state, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

  defp child_state(id) do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, id)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid).assigns.state
  end

  defp active_buffer do
    {:ok, snapshot} = Quillex.Buffer.fetch(root_state().active_buf)
    snapshot
  end

  spex "the keyboard belongs to one pane at a time" do
    scenario "clicking the editor takes the keyboard off the project search pane" do
      given_ "a query typed into an open project search pane", context do
        fresh_editor!()
        Process.sleep(400)

        Probes.send_keys("f", [:ctrl, :shift])
        Process.sleep(1_200)

        assert root_state().show_project_search, "Ctrl+Shift+F should open the pane"

        Probes.send_text("hello")
        Process.sleep(600)

        assert child_state(:project_search_pane).focused, "the pane should hold the keyboard"
        refute child_state(:buffer_pane).focused, "the editor should have let go of it"

        {:ok, context}
      end

      when_ "the person clicks into the editor and types", context do
        ensure_editor_focused()
        Process.sleep(400)

        Probes.send_text("XYZ")
        Process.sleep(800)

        {:ok, context}
      end

      then_ "the typing went to the document and nowhere else", context do
        pane = child_state(:project_search_pane)

        refute pane.focused,
               "the pane still holds the keyboard, so it is typing into the query too"

        assert child_state(:buffer_pane).focused, "the editor should have taken it"
        assert root_state().keyboard_owner == :buffer

        assert pane.query == "hello",
               "typing leaked into the query field: #{inspect(pane.query)}"

        assert Enum.at(active_buffer().lines, 0) == "XYZ"

        {:ok, context}
      end
    end
  end
end
