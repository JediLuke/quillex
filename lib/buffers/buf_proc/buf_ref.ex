defmodule Quillex.Structs.BufState.BufRef do
  @moduledoc """
  A BufRef is just a minified reference to a full buffer. They exist because
  buffers hold state, sometimes a lot of it, and I often only care about
  the highest level, referencial data for a buffer - so I created this struct
  for those situations. The BufRef holds just enough data to work like a pointer
  to the real buffer, plus some small amounts of metadata where that is useful,
  e.g. we need to know the mode at the highest level of the app's state tree, so
  that we know how to route user input (pressing Enter does different things in
  insert vs normal mode in Vim) so we keep track of that here when it's practical.

  We don't keep track of the pids of buffer processes any more, because they can
  always go stale, instead I prefer the extra expense of calling `fetch_buf`
  """

  @type t :: %__MODULE__{
    uuid: String.t() | nil,
    name: String.t() | nil,
    mode: atom() | {atom(), atom()} | nil,
    dirty?: boolean()
  }

  defstruct [
    :uuid,
    :name,
    # we need mode in the buf_ref because the buf_ref gets stored in the RadixState,
    # and we need to know the mode to decide how to handle user input
    :mode,
    # dirty? tracks whether the buffer has unsaved changes - used by the tab bar
    # to display a visual indicator (e.g. " *" suffix on the tab label)
    dirty?: false
  ]

  @doc """
  Generate a `BufRef` from a full `BufState`. Extracts only the fields needed
  for routing and display (uuid, name, mode, dirty?).
  """
  @spec generate(Quillex.Structs.BufState.t()) :: t()
  def generate(%Quillex.Structs.BufState{} = buf) do
    %__MODULE__{
      uuid: buf.uuid,
      name: buf.name,
      mode: buf.mode,
      dirty?: buf.dirty?
    }
  end

  # Dont use this one use Quillex.Buffer.Process.fetch_buf
  # def fetch_buf(%__MODULE__{} = buf_ref) do
  #   Quillex.Buffer.BufferManager.call_buffer(buf_ref, :get_state)
  # end
end
