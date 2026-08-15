defmodule Quillex.GUI.ResizeScheduler do
  @moduledoc """
  Pure state machine used to coalesce bursts of viewport reshape events.

  Window managers can emit hundreds of intermediate sizes during one drag.
  Rendering every obsolete size creates an ever-growing mailbox backlog. The
  scheduler retains only the newest size and permits one render timer at a
  time, giving the UI frame-paced, trailing-edge updates.
  """

  @type size :: {pos_integer(), pos_integer()}
  @type t :: %{pending: size() | nil, scheduled?: boolean()}

  @spec new() :: t()
  def new, do: %{pending: nil, scheduled?: false}

  @spec enqueue(t(), size()) :: {t(), :schedule | :already_scheduled}
  def enqueue(%{scheduled?: false} = state, size),
    do: {%{state | pending: size, scheduled?: true}, :schedule}

  def enqueue(state, size), do: {%{state | pending: size}, :already_scheduled}

  @spec take(t()) :: {size() | nil, t()}
  def take(state), do: {state.pending, %{state | pending: nil, scheduled?: false}}
end
