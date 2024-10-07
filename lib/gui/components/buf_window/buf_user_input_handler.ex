defmodule Quillex.GUI.Components.Buffer.UserInputHandler do
  @moduledoc """
  Handles user input for the FluxBuffer component.
  """
  use ScenicWidgets.ScenicEventsDefinitions
  require Logger

  def handle(rdx, @right_arrow) do
    Logger.warn("#{__MODULE__} getting RIGHT ARROW")
    [{:move_cursor, :right, 1}]
  end

  def handle(rdx, any_input) do
    Logger.warn("#{__MODULE__} ignoring input: #{inspect(any_input)}")
    :ignore
  end
end

# alias Flamelex.GUI.Component.Editor
# alias Flamelex.Fluxus.RadixState
# alias Flamelex.GUI.Component.Editor

# TODO we shouldn't do this on the entire radix state, just the editor state
# def handle(%Editor.State{} = _s, input) do
# def handle(rdx, input) do
#   case input do
#     # Match on specific inputs and return actions
#     _ ->
#       Logger.warn("#{__MODULE__} received unhandled input: #{inspect(input)}")
#       :ignore
#   end
# end

# def handle(%RadixState{} = rdx, @left_arrow) do
#   Logger.warn("#{__MODULE__}getting LEFRT ARROWWW")
#   :ignore
# end

# def handle(%RadixState{} = rdx, @right_arrow) do
#   [{Editor.Reducer, {:move_cursor, :right, 1}}]
# end

# On State

# With this, I have introduced a hodge=podge colection
# of state thats spread thgouthought the whole application...

# ultimately its true though that all events get routed through one central
# chokepoint called RadixStore, yes state may also now exist within memory
# of the GUI components - this was the way Scenic was always designed,
# and it's just the way that it wants to work, even though that's not
# really compatible with how _I_ want to do things (Flux architecture)

# Ultaimtely though yes some state may get spread out but as long as were
# careful, none of that state will ever be the important stuff
# that we need to know in order to make decisions about how to handle
# any inputs or actions - the location of the cursor has no meaning to
# anything other than the GUI component that's drawing it (MAYBE some external program
# that wants to interact with the buffer may want to know where cursors are,
# in which case, it can always query the GUI component!) - but point is
# there's no action that gets altered depending on where the cursor is,
# if ther is it's a higher level state change anyway so handle it within radix state

# def handle(%RadixState{} = _rdx, input) do
#   Logger.warn("#{__MODULE__} ignoring input: #{inspect(input)}")
#   :ignore
# end

# def handle(%Editor.State{} = state, @right_arrow) do
#   # Flamelex.Lib.Utils.PubSub.broadcast(
#   #   topic: {:buffers, hd(state.buffers).uuid},
#   #   msg: {:move_cursor, :right, 1}
#   # )

#   Quillex.Buffer.BufferManager.cast_to_buffer(
#     hd(state.buffers).uuid,
#     {:user_input_fwd, @right_arrow}
#   )

#   :re_routed
# end

# def handle(%Editor.State{} = _s, @down_arrow) do
#   IO.puts("CAN GET A DOWN ARROW")
#   :ignore
# end

# def handle(%Editor.State{} = _s, any_ii) do
#   IO.puts("ignoring #{inspect(any_ii)} but at least we got here")
#   :ignore
# end
