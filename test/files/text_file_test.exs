defmodule Quillex.Files.TextFileTest do
  use ExUnit.Case, async: true

  alias Quillex.Files.TextFile

  @tag :tmp_dir
  test "accepts UTF-8 text", %{tmp_dir: root} do
    path = Path.join(root, "unicode.txt")
    File.write!(path, "hello, λ\n")

    assert TextFile.read(path) == {:ok, "hello, λ\n"}
  end

  @tag :tmp_dir
  test "rejects invalid UTF-8 and NUL-containing files", %{tmp_dir: root} do
    invalid = Path.join(root, "invalid.bin")
    nul = Path.join(root, "nul.bin")
    File.write!(invalid, <<0xFF, 0xFE, 0xFD>>)
    File.write!(nul, <<"valid", 0, "utf8">>)

    assert TextFile.read(invalid) == {:error, :binary_file}
    assert TextFile.read(nul) == {:error, :binary_file}
  end
end
