defmodule Quillex.Files.TextFile do
  @moduledoc """
  Safe disk boundary for content that will enter Quillex's text model.

  Scenic text primitives and Quillex's cursor/column operations require valid
  UTF-8. Executables and many other binary formats also contain NUL bytes that
  are not meaningful editor text. Rejecting both here prevents arbitrary file
  bytes from reaching string algorithms, font measurement, or the renderer.
  """

  @spec read(Path.t()) :: {:ok, binary()} | {:error, File.posix() | :binary_file}
  def read(path) when is_binary(path) do
    with {:ok, content} <- File.read(path),
         :ok <- validate(content) do
      {:ok, content}
    end
  end

  @spec validate(binary()) :: :ok | {:error, :binary_file}
  def validate(content) when is_binary(content) do
    if String.valid?(content) and :binary.match(content, <<0>>) == :nomatch,
      do: :ok,
      else: {:error, :binary_file}
  end
end
