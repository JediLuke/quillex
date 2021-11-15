defmodule QuillEx.StageManager do
    use GenServer
    require Logger

    # Everything runs through StageManager - it's the chokepoint/bottleneck
    # of the whole system - but it's also where all data syncronization
    # happens, so we just have to live with it.
    #
    # For this app, it's my hypothesis that storing all the state in one
    # single global Agent process, using StageManager (maybe I should have
    # called this `Spielberg` or something) to syncronously (we use calls)
    # update the state & broadcast changes out to the GUI. Those GUI
    # components react to these broadcasts - they check their own internal
    # state - so they discard any messags which don't affect them, just
    # by checking if they have the same state. If their state has updated,
    # they will re-compute & update their Scenic.Graph{}, and push it
    # too.
  
    def start_link(_args) do
        GenServer.start_link(__MODULE__, %{})
    end
    
    def init(_args) do
      Logger.debug "#{__MODULE__} initializing..."
      Process.register(self(), __MODULE__)
      {:ok, :state} # Latin for "initial_state" (*citation required)
    end
  

    # def handle_call(:pop, _from, [head | tail]) do
    #   {:reply, head, tail}
    # end

    # def handle_call({:open, msg}, _from, :initium) do
    def handle_call({:open, %{file: file, text: t}}, _from, :state) do
        Logger.debug "#{__MODULE__} handling call: :open_file"

        #TODO get the RadixState

        # new RadixState <- reducer(RadixState, action)
        # broadcast RadixState - components potentially re-draw

        file = "Luke"
        # IO.inspect msg
        Logger.debug "#{__MODULE__} opening file: #{inspect file}"
        #TODO this would be best if we had a struct, & a changeset (though slower?)
        new_state = %{
            files: [{:active, file}],
            text: t
        }

        # BC the changes
        QuillEx.Utils.PubSub.broadcast(state_change: new_state)

        # Update the Radix

        # return everything
        {:reply, :ok, :state}
    end
  

    # def handle_cast({:push, element}, state) do
    #   {:noreply, [element | state]}
    # end
  end