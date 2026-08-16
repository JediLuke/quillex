defmodule Quillex.Buffer.Ref do
  @moduledoc """
  Stable, lightweight identity for a document managed by `Quillex.Buffer`.

  The UUID is the process identity; `path` is canonical when present.  Mutable
  editor content deliberately does not live in this value.
  """

  @enforce_keys [:uuid, :name]
  defstruct [:uuid, :name, :path, dirty?: false, read_only?: false, external_change: nil]

  @type t :: %__MODULE__{
          uuid: String.t(),
          name: String.t(),
          path: String.t() | nil,
          dirty?: boolean(),
          read_only?: boolean(),
          external_change: nil | :modified | :deleted
        }

  @doc false
  def from_internal(%{uuid: uuid, name: name} = ref) do
    %__MODULE__{
      uuid: uuid,
      name: name,
      path: Map.get(ref, :path) || source_path(Map.get(ref, :source)),
      dirty?: Map.get(ref, :dirty?, false),
      read_only?: Map.get(ref, :read_only?, false),
      external_change: Map.get(ref, :external_change)
    }
  end

  def generate(state), do: from_internal(state)

  defp source_path(%{filepath: path}) when is_binary(path),
    do: Quillex.Buffer.PathIdentity.canonical(path)

  defp source_path(_), do: nil
end
