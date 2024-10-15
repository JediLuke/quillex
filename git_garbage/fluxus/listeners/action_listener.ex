defmodule QuillEx.Fluxus.ActionListener do
  @moduledoc """
  This process listens to events on the :general topic, and if they're
  actions, makes stuff happen.
  """
  use GenServer
  require Logger

  # In quillex, I'm going to _keep_ the concept of the action listener
  # this is an experiment in the idea of keeping radix store almost
  # purely as a state store only, and it doesn't do anything inside that
  # process

  # in flamelex on the other hand, at least right now, the store is very
  # important place that state is stored & it farms out work via wormhole
  # so that it's pretty safe, but could still potentially crash

  # I should also measure the memory differences between the 2 approaches
  # because one fear I have of doing it the quillex way is that I'm going
  # to be passing around a lot of memory between processes, and that could
  # be costly

  # note I may end up changing my mind on this but right now
  # it doesnt matter anywy cause I finally figured out how to
  # embed quillex inside flamelex properly and the quillex gui is a later
  # days concern

  @topic :quill_ex_actions

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_args) do
    Logger.debug("#{__MODULE__} initializing...")
    EventBus.subscribe({__MODULE__, [to_string(@topic)]})
    {:ok, %{}}
  end

  def process({@topic, _id} = event_shadow) do
    event = EventBus.fetch_event(event_shadow)

    if not an_action?(event) do
      :ignore
    else
      %{data: {:action, action}} = event
      radix_state = QuillEx.Fluxus.RadixStore.get()

      case QuillEx.Fluxus.RadixReducer.process(radix_state, action) do
        x when x in [:ignore, :ok] ->
          EventBus.mark_as_completed({__MODULE__, event_shadow})
          # Logger.debug "#{__MODULE__} ignoring... #{inspect(%{action: action})}"
          # Logger.debug "#{__MODULE__} ignoring... #{inspect(%{radix_state: radix_state, action: action})}"
          :ignore

        {:ok, ^radix_state} ->
          EventBus.mark_as_completed({__MODULE__, event_shadow})

          # Logger.debug "#{__MODULE__} ignoring (no state-change)... #{inspect(%{radix_state: radix_state, action: action})}"
          # Logger.debug "#{__MODULE__} ignoring (no state-change)..."
          :ignore

        {:ok, new_radix_state} ->
          # Logger.debug "#{__MODULE__} processed event, state changed..."
          # Logger.debug "#{__MODULE__} processed event, state changed... #{inspect(%{radix_state: radix_state, action: action})}"
          QuillEx.Fluxus.RadixStore.update(new_radix_state)
          EventBus.mark_as_completed({__MODULE__, event_shadow})
          {:ok, new_radix_state}

        {:error, reason} ->
          Logger.error("Unable to process event: #{inspect(reason)}")
          # EventBus.mark_as_completed({__MODULE__, event_shadow})
          raise reason
      end
    end
  end

  # def handle_action

  defp an_action?(%EventBus.Model.Event{topic: @topic, data: {:action, _a}}), do: true
  defp an_action?(_otherwise), do: false
end
