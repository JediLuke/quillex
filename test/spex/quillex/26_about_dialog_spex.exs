defmodule Quillex.AboutDialogSpex do
  @moduledoc """
  Phase 26: Help → About splash (Roadmap 3.6 / QA A7)

  The About box is a `ScenicWidgets.PopupModal`: dimmed overlay, centred
  panel with the Chopin quote from commit #1, dismissed by Escape/Enter/OK.
  Dismissing must hand keyboard focus back to the editor.

  Assertions use ScriptInspector (actually-drawn text) because the modal's
  content is plain text primitives, not semantic elements.
  """
  use SexySpex

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(2000)

    # Known LAYOUT to start from (overlays dismissed, file navigator
    # closed) without touching buffers — an open navigator shifts the
    # editor pane 250px right and makes fixed-x clicks miss it.
    Quillex.TestHelpers.AppReset.reset_layout!()
    :ok
  end

  spex "About dialog shows the splash and returns focus on dismiss",
    description: "Help → About renders the Chopin splash; Escape dismisses and typing resumes",
    tags: [:phase_26, :about, :dialog] do
    scenario "Open About from the Help menu, then dismiss with Escape" do
      given_ "the app is idle", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)
        {:ok, context}
      end

      when_ "the user opens Help → About", context do
        Probes.click_element("icon_menu_help")
        Process.sleep(200)
        Probes.click_element("icon_menu_help_about")
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the splash is on screen with the founding quote", context do
        assert ScriptInspector.rendered_text_contains?("Simplicity is the highest goal"),
               "the About splash (Chopin quote) is not on screen"

        assert ScriptInspector.rendered_text_contains?("github.com/JediLuke/quillex"),
               "the About splash is missing the project link"

        Quillex.TestHelpers.Invariants.assert_invariants!()
        {:ok, context}
      end
    end

    scenario "Escape dismisses and the editor gets focus back" do
      given_ "the About splash is open", context do
        assert ScriptInspector.rendered_text_contains?("Simplicity is the highest goal")
        {:ok, context}
      end

      when_ "the user presses Escape and then types", context do
        Probes.send_keys("escape", [])
        Process.sleep(400)
        Probes.send_text("after about")
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the splash is gone and the typing landed in the editor", context do
        refute ScriptInspector.rendered_text_contains?("Simplicity is the highest goal"),
               "the About splash did not dismiss on Escape"

        assert ScriptInspector.rendered_text_contains?("after about"),
               "typing after dismissing About did not reach the editor — focus not returned"

        Quillex.TestHelpers.Invariants.assert_invariants!()
        {:ok, context}
      end
    end
  end
end
