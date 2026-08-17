defmodule Quillex.CLI do
  @moduledoc """
  Support for launching Quillex from a shell: `qlx`, `qlx notes.txt`, `qlx .`

  `bin/qlx` has to run `mix` from the project directory, so it hands the
  shell's context across in the environment instead:

      QLX_CWD    — the directory the user ran `qlx` from
      QLX_TARGET — the path argument, made absolute (absent if none was given)

  Two hooks, and their boot order is the whole design:

    * `chdir!/0` runs at the top of `Quillex.App.start/2`, before any child
      starts. Everything downstream reads `File.cwd!()` — the file-nav sidebar
      most of all, which ViewStore seeds in its `init` — so the VM's cwd has
      to be the user's cwd before the stores boot, not after.

    * the child returned by `child_spec/1` opens the target file. It sits
      between the buffer supervisor and Scenic so the buffer already exists
      when `RootScene.init` runs — the scene only conjures a scratch buffer
      when it finds the list empty.

  When neither variable is set (an `iex -S mix` session) both hooks are no-ops
  and the app boots exactly as it always has.
  """

  @cwd_var "QLX_CWD"
  @target_var "QLX_TARGET"

  @doc "True when this VM was started by `bin/qlx` rather than `iex -S mix`."
  def launched_from_cli?, do: System.get_env(@cwd_var) != nil

  @doc """
  Adopt the shell's working directory.

  `qlx path/to/dir` treats the directory itself as the working directory — it
  is the same gesture as `cd path/to/dir && qlx .`, and the file tree should
  show what was asked for. For a file argument (or none) the shell's own cwd
  is what the user means.
  """
  def chdir! do
    case working_dir() do
      nil -> :ok
      dir -> File.cd!(dir)
    end
  end

  defp working_dir do
    case System.get_env(@target_var) do
      nil -> System.get_env(@cwd_var)
      target -> if File.dir?(target), do: target, else: System.get_env(@cwd_var)
    end
  end

  # A boot step, not a process: the work is finished by the time start_link
  # returns, so it reports `:ignore` and leaves nothing behind to supervise.
  @doc false
  def child_spec(_opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}, restart: :temporary}
  end

  @doc false
  def start_link do
    open_target(System.get_env(@target_var))
    :ignore
  end

  defp open_target(nil), do: :ignore

  defp open_target(path) do
    if File.dir?(path) do
      # A directory has no buffer to open — show the tree instead. Its path is
      # already the cwd, which is what ViewStore seeded file_nav_path from.
      Quillex.RadixCache.ViewStore.open_file_nav()
    else
      {:ok, _info} = Quillex.API.FileAPI.open(path)
    end

    :ignore
  end
end
