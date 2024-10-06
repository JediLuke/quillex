defmodule Quillex.Structs.Buffer.BufRef do
  defstruct [
    :uuid,
    # :id,
    :pid,
    :name
  ]

  def generate(%QuillEx.Structs.Buffer{} = buf, pid) when is_pid(pid) do
    %__MODULE__{
      uuid: buf.uuid,
      name: buf.name,
      pid: pid
    }
  end
end
