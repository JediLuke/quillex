
defmodule QuillEx.RootScene.State do
  use StructAccess

  defstruct [
    frame: nil,
    tabs: [],
    toolbar: nil,
    buffers: [],
    active_buf: nil
  ]

  def new(%{frame: %Widgex.Frame{} = frame, buffers: buffers}) when is_list(buffers) do
    %__MODULE__{
      frame: frame,
      toolbar: %{
        height: 50
      },
      buffers: buffers,
      active_buf: 1
    }
  end

  def active_buf(%{assigns: %{state: state}}) do
    active_buf(state)
  end

  def active_buf(%__MODULE__{} = state) do
    # we count buffers starting at one, need to offset this cause Elixir uses zero for Enums
    Enum.at(state.buffers, state.active_buf - 1)
  end
end
