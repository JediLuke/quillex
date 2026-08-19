defmodule Quillex.SettingsFile do
  @moduledoc """
  The saved defaults: the settings Quillex starts with.

  ## Why it is explicit

  Most editors write your preferences back to disk the moment you change one.
  That is convenient right up until it isn't: you widen the tabs to read
  somebody else's file, turn line numbers off to take a screenshot, try a
  theme you end up disliking — and every one of those follows you into the
  next session, because nobody asked.

  So Quillex separates the two things that get conflated. Changing a setting
  changes THIS session and nothing else. **File → Save Settings as Default**
  is a deliberate act: it takes the settings you are looking at right now and
  makes them the ones every future session starts with. Nothing is written
  until you ask for it, and what gets written is exactly what is on screen.

  Read on boot, written on request. That is the whole contract.

  ## Where

  Wherever `Quillex.ConfigDir` says, which is the ordinary place for the
  platform: `~/.config/quillex` on Linux, `~/Library/Application Support`
  on macOS, `%APPDATA%` on Windows.

  ## What is saved

  The editor and appearance settings from `ViewStore` — the things the View
  menu changes. Layout that is really "where I was" rather than "how I like
  it" (which files were open, sidebar visibility, dialog flags) is not saved:
  session restore is a different feature, deliberately not part of 1.0.
  """

  require Logger

  # Only these. A key added to the view state does not become a saved setting
  # by accident — it has to be named here, so what persists stays a decision.
  @persisted [
    :show_line_numbers,
    :show_matching_brace,
    :highlight_current_line,
    :highlight_current_column,
    :word_wrap,
    :auto_indent,
    :tab_width,
    :text_size,
    :fold_level,
    :show_menu_shortcuts,
    :show_action_feedback,
    :syntax_highlighting,
    :theme,
    :chrome_zoom,
    :file_nav_width
  ]

  @doc "The settings file's path, whether or not it exists."
  def path do
    Quillex.ConfigDir.file("settings.json")
  end

  @doc "Which settings are saved. The About/dialog text reads this rather than repeating it."
  def persisted_keys, do: @persisted

  @doc """
  The saved settings, or an empty map when there are none.

  This is a boundary — the file is outside the program and a person may well
  have edited it — so a missing, unreadable or malformed file means "no saved
  settings" rather than a crash. A file that IS readable but holds a key we do
  not recognise loses that key and keeps the rest.
  """
  def load do
    with {:ok, body} <- File.read(path()),
         {:ok, raw} <- Jason.decode(body) do
      decode(raw)
    else
      {:error, :enoent} ->
        %{}

      {:error, reason} ->
        Logger.warning("Ignoring #{path()}: #{inspect(reason)}")
        %{}
    end
  end

  @doc """
  Write these settings as the defaults. Returns `{:ok, path}` or `{:error, reason}`.

  Called only from the menu action, never as a side effect of changing a
  setting.
  """
  def save(view) when is_map(view) do
    body =
      view
      |> Map.take(@persisted)
      |> encode()
      |> Jason.encode!(pretty: true)

    file = path()

    with :ok <- File.mkdir_p(Path.dirname(file)),
         :ok <- File.write(file, body <> "\n") do
      {:ok, file}
    end
  end

  @doc "Whether saved defaults exist."
  def exists?, do: File.exists?(path())

  # The theme is the one setting that is an atom rather than a number, string
  # or boolean, and JSON has no atoms. It round-trips through the palette's own
  # list of themes, so a hand-edited file naming a theme that no longer exists
  # is dropped instead of creating an atom for a theme nobody can render.
  defp encode(settings) do
    case settings do
      %{theme: theme} -> %{settings | theme: Atom.to_string(theme)}
      _ -> settings
    end
  end

  defp decode(raw) when is_map(raw) do
    known = Enum.map(@persisted, &{Atom.to_string(&1), &1}) |> Map.new()

    raw
    |> Enum.flat_map(fn {key, value} ->
      case Map.fetch(known, key) do
        {:ok, :theme} -> theme_pair(value)
        {:ok, atom} -> [{atom, value}]
        :error -> []
      end
    end)
    |> Map.new()
  end

  defp decode(_not_a_map), do: %{}

  defp theme_pair(name) when is_binary(name) do
    case Enum.find(Quillex.GUI.Palette.themes(), fn {id, _label} -> Atom.to_string(id) == name end) do
      {id, _label} -> [{:theme, id}]
      nil -> []
    end
  end

  defp theme_pair(_), do: []
end
