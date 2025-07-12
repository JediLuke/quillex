defmodule Quillex.GUI.Components.BufferPane.UserInputHandler do
  @moduledoc """
  Handles user input for the FluxBuffer component.
  """
  alias Quillex.GUI.Components.BufferPane.UserInputHandler.VimKeyMappings.{InsertMode, NormalMode}
  alias Quillex.GUI.Components.BufferPane.UserInputHandler.NotepadMap
  require Logger

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

  def handle(%{buf_ref: %{mode: :edit}, buf: buf}, input) do
    NotepadMap.handle(buf, input)
  end

  def handle(%{buf_ref: %{mode: {:vim, :insert}}}, input) do
    InsertMode.handle(input)
  end

  def handle(%{buf_ref: %{mode: {:vim, :normal}}}, input) do
    NormalMode.handle(input)
  end

  def handle(buf, input) do
    Logger.warning("Unhandled input - mode: #{inspect(Map.get(buf, :buf_ref, %{}) |> Map.get(:mode, :no_mode))}, input: #{inspect(input)}")
    [:ignore]
  end
end
