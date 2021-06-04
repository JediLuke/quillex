defmodule QuillEx.Structs.TextFile do
    
  defstruct path: nil,
            title: nil,
            lines: [""]

  def blank do
    %__MODULE__{}
  end
end