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
end
