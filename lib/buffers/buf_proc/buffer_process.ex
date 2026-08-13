defmodule Quillex.Buffer.Process do
  @moduledoc """
  The buffer GenServer. Runs under the Buffer supervision tree (not the GUI).

  User input is ignored here — the GUI component converts input to actions and
  sends them via `handle_call/handle_cast({:action, ...})`. Buffer state changes
  are broadcast over PubSub so the GUI can re-render.
  """
  use GenServer
  require Logger

  def fetch_buf(%{uuid: uuid} = buf_ref) when is_binary(uuid) do
    Quillex.Buffer.BufferManager.call_buffer(buf_ref, :get_state)
  end

  def start_link(%Quillex.Structs.BufState{} = buf) do
    buf_tag = {buf.uuid, __MODULE__}
    via_tuple = {:via, Registry, {Quillex.BufferRegistry, buf_tag}}
    GenServer.start_link(__MODULE__, buf, name: via_tuple)
  end

  def init(%Quillex.Structs.BufState{} = buf) do
    # Each buffer process IS a RadixCache store: it registers a retained
    # Scenic.PubSub source and publishes its full BufState after every reduce.
    Scenic.PubSub.register(Quillex.RadixCache.Sources.buffer(buf.uuid))
    Scenic.PubSub.publish(Quillex.RadixCache.Sources.buffer(buf.uuid), buf)
    {:ok, buf}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  # The cleanliness check and replacement share this process turn. A watcher
  # must not fetch "clean", race a keystroke, and then overwrite that edit.
  def handle_call({:reload_from_disk_if_clean, _lines}, _from, %{dirty?: true} = state) do
    {:reply, {:error, :dirty}, state}
  end

  def handle_call({:reload_from_disk_if_clean, lines}, _from, state) when is_list(lines) do
    case apply_actions(state, [{:reload_from_disk, lines}]) do
      {:ok, new_state} -> {:reply, {:ok, new_state}, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:action, actions}, _from, state) when is_list(actions) do
    if read_only_violation?(state, actions) do
      {:reply, {:error, :read_only}, state}
    else
      case apply_actions(state, actions) do
        {:ok, new_state} -> {:reply, {:ok, new_state}, new_state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call({:action, a}, from, state) when is_tuple(a) or is_atom(a) do
    handle_call({:action, [a]}, from, state)
  end

  # Handle async action casts from TextField (store_backed mode)
  def handle_cast({:action, actions}, state) when is_list(actions) do
    if read_only_violation?(state, actions) do
      Logger.warning("Rejected content mutation for read-only buffer #{state.uuid}")
      {:noreply, state}
    else
      case apply_actions(state, actions) do
        {:ok, new_state} ->
          {:noreply, new_state}

        {:error, reason} ->
          Logger.warning("Rejected buffer actions #{inspect(actions)}: #{inspect(reason)}")
          {:noreply, state}
      end
    end
  end

  def handle_cast({:action, a}, state) when is_tuple(a) or is_atom(a) do
    handle_cast({:action, [a]}, state)
  end

  # Clipboard shell-outs leave port-closed messages behind
  def handle_info({_port, :closed}, state) do
    {:noreply, state}
  end

  # The single reduce-and-broadcast path shared by call and cast entry points.
  defp apply_actions(state, actions) do
    result =
      Enum.reduce_while(actions, {:ok, state}, fn action, {:ok, state_acc} ->
        try do
          case apply_effect_boundary(state_acc, action) do
            %Quillex.Structs.BufState{} = new_state -> {:cont, {:ok, new_state}}
            :ignore -> {:halt, {:error, {:invalid_action, action, "unsupported action"}}}
            other -> {:halt, {:error, {:invalid_action_result, action, other}}}
          end
        rescue
          error in FunctionClauseError ->
            {:halt, {:error, {:invalid_action, action, Exception.message(error)}}}

          error ->
            {:halt, {:error, {:action_failed, action, Exception.message(error)}}}
        end
      end)

    with {:ok, new_state} <- result do
      # Edge-cast display metadata to the buffer-list store only on transition,
      # so the tab bar's Refs stay fresh without per-keystroke list publishes
      if new_state.dirty? != state.dirty? or new_state.name != state.name or
           new_state.source != state.source or
           new_state.external_change != state.external_change do
        Quillex.Buffer.BufferManager.update_buffer_meta(new_state.uuid, %{
          dirty?: new_state.dirty?,
          name: new_state.name,
          path: source_path(new_state.source),
          external_change: new_state.external_change
        })
      end

      Scenic.PubSub.publish(Quillex.RadixCache.Sources.buffer(new_state.uuid), new_state)

      {:ok, new_state}
    end
  end

  defp source_path(%{filepath: path}) when is_binary(path), do: path
  defp source_path(_source), do: nil

  # Clipboard access is an effect and therefore belongs at the process shell,
  # never in the pure editing reducer. Effectful commands are translated into
  # ordinary document actions only after their side effect succeeds.
  defp apply_effect_boundary(%{selection: nil} = state, {:copy, :selection}), do: state
  defp apply_effect_boundary(%{selection: nil} = state, {:cut, :selection}), do: state

  defp apply_effect_boundary(state, {:copy, :selection}) do
    state |> selected_text() |> copy_to_clipboard()
    state
  end

  defp apply_effect_boundary(state, {:cut, :selection}) do
    case state |> selected_text() |> Quillex.Buffer.ClipboardAdapter.copy_result() do
      :ok ->
        Quillex.Buffer.Process.Reducer.process(state, {:delete, :selection})

      {:error, reason} ->
        clipboard_failed(:cut, reason)
        state
    end
  end

  defp apply_effect_boundary(state, {:yank, :line, :under_cursor}) do
    state.data |> Enum.at(state.cursor.line - 1, "") |> copy_to_clipboard()
    state
  end

  defp apply_effect_boundary(state, {:paste, :at_cursor}) do
    case Quillex.Buffer.ClipboardAdapter.paste_result() do
      text when is_binary(text) ->
        Quillex.Buffer.Process.Reducer.process(state, {:insert, text, :at_cursor})

      {:error, reason} ->
        clipboard_failed(:paste, reason)
        state
    end
  end

  defp apply_effect_boundary(state, {:paste, :line, :at_cursor}) do
    case Quillex.Buffer.ClipboardAdapter.paste_result() do
      text when is_binary(text) ->
        Quillex.Buffer.Process.Reducer.process(
          state,
          {:insert, :line, text, :below_cursor_line}
        )

      {:error, reason} ->
        clipboard_failed(:paste, reason)
        state
    end
  end

  defp apply_effect_boundary(state, action),
    do: Quillex.Buffer.Process.Reducer.process(state, action)

  defp copy_to_clipboard(text) do
    case Quillex.Buffer.ClipboardAdapter.copy_result(text) do
      :ok -> :ok
      {:error, reason} -> clipboard_failed(:copy, reason)
    end
  end

  defp clipboard_failed(operation, reason) do
    label = operation |> Atom.to_string() |> String.capitalize()
    Quillex.RadixCache.ViewStore.show_status("#{label} failed: #{reason}", :error)
    :error
  end

  defp selected_text(%{data: lines, selection: %{start: start_pos, end: end_pos}}) do
    {{start_line, start_col}, {end_line, end_col}} =
      if start_pos <= end_pos, do: {start_pos, end_pos}, else: {end_pos, start_pos}

    lines
    |> Enum.slice((start_line - 1)..(end_line - 1))
    |> Enum.with_index(start_line)
    |> Enum.map_join("\n", fn {line, line_no} ->
      from = if line_no == start_line, do: start_col - 1, else: 0
      to = if line_no == end_line, do: end_col - 1, else: String.length(line)
      String.slice(line, from, max(to - from, 0))
    end)
  end

  defp read_only_violation?(%{read_only?: false}, _actions), do: false

  defp read_only_violation?(%{read_only?: true}, actions) do
    Enum.any?(actions, &mutating_action?/1)
  end

  defp mutating_action?({action, _})
       when action in [:delete, :newline, :indent, :unindent, :set_data, :cut],
       do: true

  defp mutating_action?({action, _, _}) when action in [:insert, :replace, :replace_all], do: true
  defp mutating_action?({:insert, _, _, _}), do: true
  defp mutating_action?({:paste, _}), do: true
  defp mutating_action?({:paste, _, _}), do: true
  defp mutating_action?(:delete_line), do: true
  defp mutating_action?(:empty_buffer), do: true
  defp mutating_action?(:undo), do: true
  defp mutating_action?(:redo), do: true
  defp mutating_action?(_), do: false
end
