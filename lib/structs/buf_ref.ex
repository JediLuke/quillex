defmodule Quillex.Structs.Buffer.BufRef do
  defstruct [
    :uuid,
    :pid,
    :name,
    # we need mode in the buf_ref because the buf_ref gets stored in the RadixState,
    # and we need to know the mode to decide how to handle user input
    :mode
    # TODO needs a source, for filenames - we will try without it for a while & see
  ]

  def generate(%Quillex.Structs.Buffer{} = buf, pid) when is_pid(pid) do
    %__MODULE__{
      uuid: buf.uuid,
      name: buf.name,
      pid: pid,
      mode: buf.mode
    }
  end
end
