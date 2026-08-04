defmodule Quillex.Buffer.PathIdentity do
  @moduledoc false

  @spec canonical(String.t()) :: String.t()
  def canonical(path) when is_binary(path) do
    expanded = Path.expand(path)

    case :file.read_link_all(String.to_charlist(expanded)) do
      {:ok, resolved} -> resolved |> List.to_string() |> Path.expand()
      {:error, _reason} -> expanded
    end
  end
end
