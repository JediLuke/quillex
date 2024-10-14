defmodule Quillex.GUI.Components.Buffer.Mutator do
  @valid_modes [:edit, :presentation, {:vim, :normal}, {:vim, :insert}, {:vim, :visual}]

  def set_mode(buf, mode) when mode in @valid_modes do
    %{buf | mode: mode}
  end
end
