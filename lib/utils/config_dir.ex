defmodule Quillex.ConfigDir do
  @moduledoc """
  Where this editor keeps the files a person is meant to edit.

  Every platform has an opinion about this and they disagree, so asking once
  here is better than three modules each inventing `~/.config` and being wrong
  on two platforms out of three:

  - **Linux/BSD** — `$XDG_CONFIG_HOME/quillex`, or `~/.config/quillex`
  - **macOS** — `~/Library/Application Support/Quillex`
  - **Windows** — `%APPDATA%\\Quillex`

  `XDG_CONFIG_HOME` wins everywhere it is set, including on macOS: someone who
  has gone to the trouble of setting it has said where they want their
  configuration, and second-guessing that is rude.
  """

  @doc "The directory. Not created — the thing that writes a file makes it."
  def path do
    case System.get_env("XDG_CONFIG_HOME") do
      dir when is_binary(dir) and dir != "" -> Path.join(dir, "quillex")
      _ -> platform_default()
    end
  end

  @doc "A file inside it."
  def file(name) when is_binary(name), do: Path.join(path(), name)

  defp platform_default do
    case :os.type() do
      {:unix, :darwin} ->
        Path.join([System.user_home!(), "Library", "Application Support", "Quillex"])

      {:win32, _} ->
        case System.get_env("APPDATA") do
          dir when is_binary(dir) and dir != "" -> Path.join(dir, "Quillex")
          _ -> Path.join([System.user_home!(), "AppData", "Roaming", "Quillex"])
        end

      _ ->
        Path.join([System.user_home!(), ".config", "quillex"])
    end
  end
end
