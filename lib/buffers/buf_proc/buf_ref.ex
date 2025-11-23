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

  defstruct [
    :uuid,
    :name,
    # we need mode in the buf_ref because the buf_ref gets stored in the RadixState,
    # and we need to know the mode to decide how to handle user input
    :mode
    # TODO needs a source, for filenames - we will try without it for a while & see
  ]

  def generate(%Quillex.Structs.BufState{} = buf) do
    %__MODULE__{
      uuid: buf.uuid,
      name: buf.name,
      mode: buf.mode
    }
  end

  # Dont use this one use Quillex.Buffer.Process.fetch_buf
  # def fetch_buf(%__MODULE__{} = buf_ref) do
  #   Quillex.Buffer.BufferManager.call_buffer(buf_ref, :get_state)
  # end
end
