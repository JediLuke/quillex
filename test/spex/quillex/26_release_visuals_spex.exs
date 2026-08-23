defmodule Quillex.ReleaseVisualsSpex do
  @moduledoc "Captures the material 0.7.3 UI states used by the release handoff."
  use SexySpex

  alias ScenicMcp.{Probes, Query}

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

  spex "0.7.3 release visual evidence",
    description: "Capture menus, SideNav, dialogs, tab overflow, folding, and dirty close",
    tags: [:release, :screenshots] do
    scenario "material UI states have durable captures" do
      given_ "the baseline editor is visible", context do
        capture!("073_baseline_editor")
        {:ok, context}
      end

      when_ "the typed View menu is open", context do
        Probes.click_element("icon_menu_view")
        Process.sleep(250)
        assert Query.text_visible?("Text Size")
        capture!("073_typed_view_menu")
        {:ok, context}
      end

      when_ "the file navigator is visible", context do
        Probes.click_element("icon_menu_view_file_nav")
        Process.sleep(500)
        assert Query.text_visible?("mix.exs")
        capture!("073_side_nav")
        {:ok, context}
      end

      when_ "the generated shortcuts dialog is open", context do
        Probes.click_element("icon_menu_help")
        Process.sleep(200)
        Probes.click_element("icon_menu_help_shortcuts")
        Process.sleep(300)
        assert Query.text_visible?("Keyboard Shortcuts")
        capture!("073_shortcuts_modal")
        Probes.send_keys("escape", [])
        Process.sleep(200)
        {:ok, context}
      end

      when_ "tabs overflow their available width", context do
        for n <- 1..16, do: {:ok, _} = Quillex.Buffer.new(%{name: "overflow-#{n}"})
        Process.sleep(700)
        capture!("073_tab_overflow")
        {:ok, context}
      end

      when_ "an indented document is folded", context do
        {:ok, ref} =
          Quillex.Buffer.new(%{
            name: "folding-demo.ex",
            data: ["defmodule Demo do", "  def hello do", "    :world", "  end", "end"]
          })

        :ok = Quillex.Buffer.activate(ref)
        Process.sleep(500)
        Probes.click(500, 80)
        Probes.send_keys("[", [:ctrl, :alt])
        Process.sleep(300)
        capture!("073_folding")
        {:ok, context}
      end

      when_ "a dirty native-close request is deferred", context do
        {:ok, ref} = Quillex.Buffer.new(%{name: "dirty-close-demo"})
        {:ok, _} = Quillex.Buffer.dispatch(ref, {:insert, "unsaved", :at_cursor})

        send(
          Process.whereis(Quillex.RootScene),
          {:quit_requested, Quillex.Buffer.dirty_buffers()}
        )

        Process.sleep(350)
        assert Query.text_visible?("Quit Without Saving")
        capture!("073_dirty_close")
        Quillex.TestHelpers.AppReset.reset!()
        {:ok, context}
      end
    end
  end

  defp capture!(name) do
    content = Query.rendered_text()
    assert is_binary(content) and content != "", "missing semantic capture #{name}"

    if System.get_env("QUILLEX_CAPTURE_RELEASE") == "1" do
      artifact_dir = Path.expand("../../../docs/captures/0.7.3", __DIR__)
      File.mkdir_p!(artifact_dir)
      File.write!(Path.join(artifact_dir, "#{name}.txt"), content)
    end
  end
end
