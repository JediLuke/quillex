defmodule Quillex.SavedSettingsSpex do
  @moduledoc """
  View → Save Settings as Default.

  Changing a setting changes this session. Making it the setting every session
  starts with is a separate, deliberate act, and it explains itself before it
  writes anything — because it is the only thing in the menus that outlives
  the window you are looking at.
  """
  use SexySpex

  alias ScenicMcp.Probes
  alias Quillex.RadixCache.ViewStore

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
    end

    Process.sleep(1_500)
    Quillex.TestHelpers.AppReset.reset!()

    # Somewhere disposable: this spex writes a real settings file, and the
    # person running it has one of their own.
    dir = Path.join(System.tmp_dir!(), "qlx_spex_settings_#{System.unique_integer([:positive])}")
    System.put_env("XDG_CONFIG_HOME", dir)
    on_exit(fn -> File.rm_rf(dir) end)

    Process.sleep(500)
    :ok
  end

  defp root_state, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

  defp menu(menu_id, item_id) do
    Probes.click_element("icon_menu_#{menu_id}")
    Process.sleep(500)
    Probes.click_element("icon_menu_#{menu_id}_#{item_id}")
    Process.sleep(600)
  end

  spex "settings become defaults only when asked" do
    scenario "saving the current settings as the default" do
      given_ "a setting changed in this session", context do
        # Start from a plain editor: a spex that runs after the project search
        # one inherits its open pane, and a menu click lands somewhere else
        # entirely. Passing alone and failing in company is the least useful
        # way for a test to fail.
        Quillex.RadixCache.ViewStore.close_project_search()
        Quillex.RadixCache.ViewStore.sync()
        Quillex.TestHelpers.Integration.close_search_bar_if_open()
        Process.sleep(400)

        refute Quillex.SettingsFile.exists?(),
               "nothing should have been written just by changing settings"

        ViewStore.set_tab_width(8)
        ViewStore.sync()
        Process.sleep(400)

        assert ViewStore.get_state().tab_width == 8

        refute Quillex.SettingsFile.exists?(),
               "changing a setting must not write anything to disk"

        {:ok, context}
      end

      when_ "the person chooses View → Save Settings as Default", context do
        menu(:view, "save_default_settings")

        assert root_state().show_save_settings_prompt,
               "it should explain itself before writing anything"

        {:ok, context}
      end

      then_ "confirming writes the settings that are on screen", context do
        # ConfirmDialog answers to the keyboard: its buttons carry the
        # actions :save, :discard and :cancel, and "d" is the one this dialog
        # labels "Save as Default".
        Probes.send_keys("d", [])
        Process.sleep(900)

        refute root_state().show_save_settings_prompt

        assert Quillex.SettingsFile.exists?(),
               "confirming should have written #{Quillex.SettingsFile.path()}"

        saved = Quillex.SettingsFile.load()
        assert saved.tab_width == 8, "the saved defaults should be what was on screen"
        assert saved.theme == ViewStore.get_state().theme

        {:ok, context}
      end

      then_ "what is saved is settings, never which files were open", context do
        body = File.read!(Quillex.SettingsFile.path())

        refute body =~ "active_buf"
        refute body =~ "buffers"
        refute body =~ "show_file_picker"

        {:ok, context}
      end
    end
  end
end
