defmodule Quillex.SettingsFileTest do
  use ExUnit.Case, async: false
  alias Quillex.SettingsFile

  setup do
    dir = Path.join(System.tmp_dir!(), "qlx_settings_#{System.unique_integer([:positive])}")
    System.put_env("XDG_CONFIG_HOME", dir)
    on_exit(fn -> File.rm_rf(dir) end)
    :ok
  end

  test "no file means no saved settings" do
    assert SettingsFile.load() == %{}
    refute SettingsFile.exists?()
  end

  test "a saved view round-trips, theme included" do
    {:ok, path} = SettingsFile.save(%{tab_width: 8, theme: :alchemical_dark, word_wrap: true})
    assert File.exists?(path)

    loaded = SettingsFile.load()
    assert loaded.tab_width == 8
    assert loaded.theme == :alchemical_dark
    assert loaded.word_wrap == true
  end

  test "only the named keys are written" do
    {:ok, path} = SettingsFile.save(%{tab_width: 8, active_buf: "secret", show_file_picker: true})
    body = File.read!(path)

    assert body =~ "tab_width"
    refute body =~ "active_buf"
    refute body =~ "show_file_picker"
  end

  test "a corrupt file is ignored rather than fatal" do
    File.mkdir_p!(Path.dirname(SettingsFile.path()))
    File.write!(SettingsFile.path(), "{not json")

    assert SettingsFile.load() == %{}
  end

  test "an unknown theme is dropped, the rest survives" do
    File.mkdir_p!(Path.dirname(SettingsFile.path()))
    File.write!(SettingsFile.path(), ~s({"theme": "no_such_theme", "tab_width": 3}))

    loaded = SettingsFile.load()
    refute Map.has_key?(loaded, :theme)
    assert loaded.tab_width == 3
  end
end
