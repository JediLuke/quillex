defmodule Quillex.Buffer.ClipboardAdapter do
  @moduledoc """
  Copy and paste from system clipboard.

  Wraps ports to system-specific utilities responsible for clipboard access.
  On Linux it prefers `wl-copy`/`wl-paste` in a Wayland session, then falls
  back to `xclip` or `xsel`. macOS uses `pbcopy`/`pbpaste`. Commands can be
  overridden through the `:quillex, :clipboard_commands` application config.
  """

  @doc """
  Copy `value` to system clipboard.

  The original `value` is always returned, so `copy/1` can be used in pipelines.

  # Examples

      iex> Quillex.Buffer.ClipboardAdapter.copy("Hello, World!")
      "Hello, World!"

      iex> Quillex.Buffer.ClipboardAdapter.copy(["Hello", "World!"])
      ["Hello", "World!"]

      iex> "Hello, World!" |> Quillex.Buffer.ClipboardAdapter.copy() |> IO.puts()
      "Hello, World"

  """
  @spec copy(iodata) :: iodata
  def copy(value) do
    copy_result(value)
    value
  end

  @doc "Copy to the system clipboard and return `:ok` or an error tuple."
  @spec copy_result(iodata) :: :ok | {:error, String.t()}
  def copy_result(value), do: copy(:os.type(), value)

  @doc """
  Copy `value` to system clipboard but throw exception if it fails.

  Identical to `copy/1`, except raise an exception if the operation fails.

  The operation may fail when running Clipboard on unsupported operating systems or with missing
  executables (check your config).
  """
  @spec copy!(iodata) :: iodata | no_return
  def copy!(value) do
    case copy_result(value) do
      :ok ->
        value

      {:error, reason} ->
        raise reason
    end
  end

  defp copy({:unix, :darwin}, value) do
    command = command(:macos, :copy, {"pbcopy", []})
    execute(command, value)
  end

  defp copy({:unix, _os_name}, value) do
    command = command(:unix, :copy, default_unix_command(:copy))
    execute(command, value)
  end

  defp copy({:win32, _os_name}, value) do
    command = command(:windows, :copy, {"clip", []})
    execute(command, value)
  end

  defp copy({_unsupported_family, _unsupported_name}, _value) do
    {:error, "Unsupported operating system"}
  end

  @doc """
  Return the contents of system clipboard.

  # Examples

      iex> Quillex.Buffer.ClipboardAdapter.paste()
      "Hello, World!"

  """
  @spec paste() :: String.t()
  def paste do
    case paste_result() do
      {:error, _reason} ->
        nil

      output ->
        output
    end
  end

  @doc "Read the system clipboard and return its contents or an error tuple."
  @spec paste_result() :: String.t() | {:error, String.t()}
  def paste_result, do: paste(:os.type())

  @doc """
  Return the contents of system clipboard but throw exception if it fails.

  Identical to `paste/1`, except raise an exception if the operation fails.

  The operation may fail when running Clipboard on unsupported operating systems or with missing
  executables (check your config).
  """
  @spec paste!() :: String.t() | no_return
  def paste! do
    case paste_result() do
      {:error, reason} ->
        raise reason

      output ->
        output
    end
  end

  defp paste({:unix, :darwin}) do
    command = command(:macos, :paste, {"pbpaste", []})
    execute(command)
  end

  defp paste({:unix, _os_name}) do
    command = command(:unix, :paste, default_unix_command(:paste))
    execute(command)
  end

  defp paste(_unsupported_os) do
    {:error, "Unsupported operating system"}
  end

  defp command(platform, operation, default) do
    quillex = Application.get_env(:quillex, :clipboard_commands, [])
    legacy = Application.get_env(:clipboard, platform, [])
    get_in(quillex, [platform, operation]) || legacy[operation] || default
  end

  defp default_unix_command(operation) do
    wayland? = System.get_env("WAYLAND_DISPLAY") not in [nil, ""]

    candidates =
      case {operation, wayland?} do
        {:copy, true} ->
          [
            {"wl-copy", []},
            {"xclip", ["-selection", "clipboard"]},
            {"xsel", ["--clipboard", "--input"]}
          ]

        {:paste, true} ->
          [
            {"wl-paste", ["--no-newline"]},
            {"xclip", ["-selection", "clipboard", "-o"]},
            {"xsel", ["--clipboard", "--output"]}
          ]

        {:copy, false} ->
          [
            {"xclip", ["-selection", "clipboard"]},
            {"xsel", ["--clipboard", "--input"]},
            {"wl-copy", []}
          ]

        {:paste, false} ->
          [
            {"xclip", ["-selection", "clipboard", "-o"]},
            {"xsel", ["--clipboard", "--output"]},
            {"wl-paste", ["--no-newline"]}
          ]
      end

    Enum.find(candidates, fn {executable, _args} -> System.find_executable(executable) end) ||
      {:unavailable,
       "No system clipboard tool found; install wl-clipboard (Wayland) or xclip/xsel (X11)"}
  end

  # Ports

  defp execute(nil), do: {:error, "Unsupported operating system"}
  defp execute({:unavailable, reason}), do: {:error, reason}

  defp execute({executable, args}) when is_binary(executable) and is_list(args) do
    case System.find_executable(executable) do
      nil ->
        {:error, "Cannot find #{executable}"}

      _ ->
        case System.cmd(executable, args) do
          {output, 0} ->
            output

          {error, _} ->
            {:error, error}
        end
    end
  end

  defp execute(nil, _), do: {:error, "Unsupported operating system"}
  defp execute({:unavailable, reason}, _value), do: {:error, reason}

  defp execute({executable, args}, value) when is_binary(executable) and is_list(args) do
    case System.find_executable(executable) do
      nil ->
        {:error, "Cannot find #{executable}"}

      path ->
        port = Port.open({:spawn_executable, path}, [:binary, args: args])

        case value do
          value when is_binary(value) ->
            send(port, {self(), {:command, value}})

          value ->
            send(port, {self(), {:command, format(value)}})
        end

        send(port, {self(), :close})

        # Wait for the port to actually close before returning
        receive do
          {^port, :closed} -> :ok
        after
          5000 -> {:error, "Clipboard operation timed out"}
        end
    end
  end

  defp format(value) do
    doc = Inspect.Algebra.to_doc(value, %Inspect.Opts{limit: :infinity})
    Inspect.Algebra.format(doc, :infinity)
  end
end
