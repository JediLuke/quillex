defmodule QuillEx.API.Buffer do
  # def switch({:buffer, _id} = buf) do
  #   Flamelex.Fluxus.action({QlxWrap, {:activate, buf}})
  # end

  # def switch(%{id: {:buffer, _id} = buf}) do
  #   switch(buf)
  # end

  # def switch(n) when n >= 1 do
  #   RadixStore.get().editor.buffers
  #   |> Enum.at(n - 1)
  #   |> switch()
  # end
end

# TODO delegate this all to quillex one day
defmodule Flamelex.API.Buffer do
  @moduledoc """
  The interface to all the Buffer commands.
  """

  # use Flamelex.Lib.ProjectAliases
  # alias Flamelex.BufferManager
  # alias Flamelex.Fluxus.RadixStore

  @doc """
  List all the open buffers.
  """
  def list do
    # todo this should call BufferManager to get the state
    Flamelex.Fluxus.RadixStore.get().apps.qlx_wrap.buffers
  end

  def new do
    # maybe this should all go through Quillex... quillex can throw
    # events back up to flamelex for GUI responsiveness... but today is not that day
    # Quillex.Fluxus.declare(rdx, q_action)

    # use declare here so that we can return the new buffer to the
    # caller of this function, providing a nice API
    {:ok, radix_state} = Flamelex.Fluxus.declare({Flamelex.GUI.Component.QlxWrap, :new_buffer})
    radix_state.apps.qlx_wrap.buffers |> List.first()
  end

  @doc """
  Open a file and load the contents into a buffer.

  This function differs from `new/1` mainly in that it takes in a _filename_
  as it's param, not the data itself.

  ## Examples

  iex> Buffer.open("README.md")
  {:buffer, {:file, "README.md"}}
  """
  def open(filepath) when is_bitstring(filepath) do
    # Flamelex.Fluxus.declare(
    {:ok, radix_state} =
      Flamelex.Fluxus.declare(
        {Flamelex.GUI.Component.QlxWrap, {:open_buffer, %{filepath: filepath}}}
      )

    # )

    radix_state.apps.qlx_wrap.buffers |> List.first()
  end

  # def new(data) when is_bitstring(data) do
  #   {:ok, radix_state} =
  #     Flamelex.Fluxus.declare(
  #       # {QuillExBufrReducer, {:open_buffer, %{data: data, mode: {:vim, :normal}}}}
  #       :new_buffer
  #     )

  #   radix_state.apps.editor.active_buf
  # end

  # this is just for convenience
  # def open({:buffer, _id} = buf), do: switch(buf)

  @doc """
  Return the active Buffer.
  """

  # def active, do: active_buf()

  # def active_buf do
  #   RadixStore.get().editor.active_buf
  # end

  # # @doc """
  # # Searches the open buffers and returns a single Buffer.id
  # # """
  # def find(search_term) do
  #   raise "Nop"
  #   # {:ok, res} = GenServer.call(BufferManager, {:find_buffer, search_term})
  #   # res
  # end

  # @doc """
  # Searches the open buffers, but raises an error if it can't find any Buffer
  # like the search_term.
  # """
  # def find!(search_term) do
  #   raise "Nop"
  #   # case GenServer.call(BufferManager, {:find_buffer, search_term}) do
  #   #   {:ok, nil} ->
  #   #     raise "Could not find any Buffer related to: #{inspect search_term}"
  #   #   {:ok, res} ->
  #   #     res
  #   # end
  # end

  # @doc """
  # Return the contents of a buffer.
  # """
  # def read(buf) do
  #   [buf] = list() |> Enum.filter(&(&1.id == buf))
  #   buf.data
  # end

  @doc """
  Make modifications or edits, to a buffer. e.g.

  ```
  insertion_op  = {:insert, "Luke is the best!", 12}
  {:ok, b}      = Buffer.find("my_buffer") #TODO still correct?

  Buffer.modify(b, insertion_op)
  ```
  """

  # # does editing actions on a buffer
  # def edit() do
  #   raise "do it"
  # end

  # def modify(%{id: buf_id}, modification) do
  #   modify(buf_id, modification)
  # end

  # def modify({:buffer, _buf_id} = buffer, modification) do
  #   Flamelex.Fluxus.action({QuillExBufrReducer, {:modify_buf, buffer, modification}})
  # end

  # @doc """
  # Scroll the buffer around.
  # """
  # def scroll({_x_scroll, _y_scroll} = scroll_delta) do
  #   Flamelex.Fluxus.action({QuillExBufrReducer, {:scroll, :active_buf, {:delta, scroll_delta}}})
  # end

  # def split do
  #   Flamelex.API.Editor.split()
  # end

  # @doc """
  # Scroll the buffer around.
  # """
  # @absolute_positions [:first_line, :last_line]
  # def move_cursor(absolute) when absolute in @absolute_positions do
  #   Flamelex.Fluxus.action({QuillExBufrReducer, {:move_cursor, :active_buf, absolute}})
  # end

  # def move_cursor({_column_delta, _line_delta} = cursor_move_delta) do
  #   Flamelex.Fluxus.action({QuillExBufrReducer, {:move_cursor, {:delta, cursor_move_delta}}})
  # end

  # @doc """
  # Tell a buffer to save it's contents.
  # """
  # def save do
  #   save(active_buf())
  # end

  # def save({:buffer, _details} = buf) do
  #   Flamelex.Fluxus.action({QuillExBufrReducer, {:save, buf}})
  # end

  # TODO
  # @doc """
  # All Buffers support show/hide
  # """
  # @impl GenServer
  # def handle_cast(:show, buf) do
  #   Flamelex.GUI.Controller.action({:show, buf})
  #   {:noreply, buf}
  # end

  # def handle_cast(:hide, buf) do
  #   Flamelex.GUI.Controller.action({:hide, buf})
  #   {:noreply, buf}
  # end

  # def close do
  #   active() |> close()
  # end

  # def close(buf) do
  #   # TODO this is causing GUI controller & VimServer to also restart??
  #   Flamelex.Fluxus.action({QuillExBufrReducer, {:close_buffer, buf}})
  # end

  # def close_all! do
  #   # raise "this should work, but is it too dangerous??"
  #   list() |> Enum.each(&close(&1))
  # end
end

# def handle_call({:find_buffer, search_term}, _from, state) do

#   #TODO move to a pure function, under a Task.Supervisor
#   similarity_cutoff = 0.72 # used to compare how similar the strings are

#   find_buf =
#     state
#     |> Enum.find(
#          :no_matching_buffer_found, # this is the default value we return if no element is found by the function below
#          fn b ->
#            # TheFuzz.compare(:jaro_winkler, search_term, b.label) >= similarity_cutoff
#            String.jaro_distance(search_term, b.label) >= similarity_cutoff
#          end)

#   case find_buf do
#     :no_matching_buffer_found ->
#       {:reply, {:error, "no matching buffer found"}, state}
#     buf ->
#       {:reply, {:ok, buf}, state}
#   end
# end

# def handle_call(:save_active_buffer, _from, state) do
#   results = state.active_buffer
#             |> ProcessRegistry.find!()
#             |> GenServer.call(:save)

#   {:reply, results, state}
# end

# def handle_call(:count_buffers, _from, state) do
#   count = Enum.count(state)
#   {:reply, count, state}
# end

#   @doc """
#   Open a blank, unsaved buffer.
#   """
#   alias QuillEx.Reducers.BufferReducer

#   def new do
#     QuillEx.action({BufferReducer, {:open_buffer, %{data: "", mode: :edit}}})
#   end

#   def new(raw_text) when is_bitstring(raw_text) do
#     QuillEx.action({BufferReducer, {:open_buffer, %{data: raw_text, mode: :edit}}})
#   end

#   @doc """
#   Return the active Buffer.
#   """
#   def active_buf do
#     QuillEx.Fluxus.RadixStore.get().editor.active_buf
#   end

#   @doc """
#   Set which buffer is the active buffer.
#   """
#   def activate(buffer_ref) do
#     QuillEx.action({BufferReducer, {:activate, buffer_ref}})
#   end

#   @doc """
#   Set which buffer is the active buffer.

#   This function does the same thing as `activate/1`, it's just another
#   entry point via the API, included for better DX (dev-experience).
#   """
#   def switch({:buffer, _name} = buffer_ref) do
#     QuillEx.action({BufferReducer, {:activate, buffer_ref}})
#   end

#   @doc """
#   Scroll the buffer around.
#   """
#   def scroll({_x_scroll, _y_scroll} = scroll_delta) do
#     QuillEx.action({BufferReducer, {:scroll, :active_buf, {:delta, scroll_delta}}})
#   end

#   @doc """
#   Scroll the buffer around.
#   """
#   def move_cursor({_column_delta, _line_delta} = cursor_move_delta) do
#     QuillEx.action({BufferReducer, {:move_cursor, {:delta, cursor_move_delta}}})
#   end

#   @doc """
#   List all the open buffers.
#   """
#   def list do
#     QuillEx.Fluxus.RadixStore.get().editor.buffers
#   end

#   def open do
#     open("./README.md")
#   end

#   def open(filepath) do
#     QuillEx.action({BufferReducer, {:open_buffer, %{filepath: filepath, mode: :edit}}})
#   end

#   def find(search_term) do
#     raise "cant find yet"
#   end

#   @doc """
#   Return the contents of a buffer.
#   """
#   def read(buf) do
#     [buf] = list() |> Enum.filter(&(&1.id == buf))
#     buf.data
#   end

#   def modify(buf, mod) do
#     QuillEx.action({BufferReducer, {:modify_buf, buf, mod}})
#   end

#   def save(buf) do
#     QuillEx.action({BufferReducer, {:save_buffer, buf}})
#   end

#   def close do
#     active_buf() |> close()
#   end

#   def close(buf) do
#     QuillEx.action({BufferReducer, {:close_buffer, buf}})
#   end
# end

# # defmodule Flamelex.Buffer.Text do
# #   @moduledoc """
# #   A buffer to hold & manipulate text.
# #   """
# #   use Flamelex.BufferBehaviour
# #   alias Flamelex.Buffer.Utils.TextBufferUtils
# #   alias Flamelex.Buffer.Utils.TextBuffer.ModifyHelper
# #   alias Flamelex.Buffer.Utils.CursorMovementUtils, as: MoveCursor
# #   # require Logger

# #   def boot_sequence(%{source: :none, data: file_contents} = params) do
# #     init_state =
# #       params |> Map.merge(%{
# #         unsaved_changes?: false,  # a flag to say if we have unsaved changes
# #         # time_opened #TODO
# #         cursors: [%{line: 1, col: 1}],
# #         lines: file_contents |> TextBufferUtils.parse_raw_text_into_lines()
# #       })

# #     {:ok, init_state}
# #   end

# #   @impl Flamelex.BufferBehaviour
# #   def boot_sequence(%{source: {:file, filepath}} = params) do
# #     # Logger.info "#{__MODULE__} booting up... #{inspect params, pretty: true}"

# #     {:ok, file_contents} = File.read(filepath)

# #     init_state =
# #       params |> Map.merge(%{
# #         data: file_contents,    # the raw data
# #         unsaved_changes?: false,  # a flag to say if we have unsaved changes
# #         # time_opened #TODO
# #         cursors: [%{line: 1, col: 1}],
# #         lines: file_contents |> TextBufferUtils.parse_raw_text_into_lines()
# #       })

# #     {:ok, init_state}
# #   end

# #   def find_supervisor_pid(%{rego_tag: rego_tag = {:buffer, _details}}) do
# #     ProcessRegistry.find!({:buffer, :task_supervisor, rego_tag})
# #   end

# #   # #TODO right now, this only works for one cursor, i.e. cursor-1
# #   # def handle_call({:get_cursor_coords, 1}, _from, %{cursors: [c]} = state) do
# #   #   {:reply, c, state}
# #   # end

# #   def handle_call(:get_num_lines, _from, state) do
# #     {:reply, Enum.count(state.lines), state}
# #   end

# #   @impl GenServer
# #   def handle_call(:save, _from, %{source: {:file, _filepath}} = state) do
# #     {:ok, new_state} = TextBufferUtils.save(state)
# #     {:reply, :ok, new_state}
# #   end

# #   def handle_cast(:close, %{unsaved_changes?: true} = state) do
# #     #TODO need to raise a bigger alarm here
# #     # Logger.warn "unable to save buffer: #{inspect state.rego_tag}, as it contains unsaved changes."
# #     {:noreply, state}
# #   end

# #   def handle_cast(:close, %{unsaved_changes?: false} = state) do
# #     Logger.debug "#{__MODULE__} received msg: :close - process will stop normally."
# #     # {:buffer, source} = state.rego_tag
# #     # Logger.warn "Closing a buffer... #{inspect source}"
# #     # ModifyHelper.cast_gui_component(source, :close)
# #     IO.puts "#TODO need to actually close the buffer - close the FIle?"

# #     # ProcessRegistry.find!({:gui_component, state.rego_tag}) #TODO this should be a GUI.Component.TextBox, not, :gui_component !!
# #     # |> GenServer.cast(:close)

# #     GenServer.cast(Flamelex.GUI.Controller, {:close, state.rego_tag})

# #     {:stop, :normal, state}
# #   end

# #   def handle_cast({:move_cursor, instructions}, state) do
# #     start_sub_task(state, MoveCursor,
# #                           :move_cursor_and_update_gui,
# #                           instructions)
# #     {:noreply, state}
# #   end

# #   # def handle_cast({:modify, details}, state) do
# #   def handle_call({:modify, details}, _from, state) do
# #     ModifyHelper.start_modification_task(state, details)
# #     # :timer.sleep(100)
# #     {:reply, :ok, state}
# #   end

# #   # when a Task completes, if successful, it will most likely callback -
# #   # so we update the state of the Buffer, & trigger a GUI update
# #   #TODO maybe this is a little ambitious... we can just do what MoveCursor does, and have the task directly call the GUI to update it specifically
# #   # def handle_cast({:state_update, new_state}, %{rego_tag: buffer_rego_tag = {:buffer, _details}}) do
# #   #   PubSub.broadcast(
# #   #     topic: :gui_update_bus,
# #   #       msg: {buffer_rego_tag, {:new_state, new_state}})
# #   #   {:noreply, new_state}
# #   # end

# #   def handle_cast({:state_update, new_state}, _old_state) do
# #     Logger.debug "#{__MODULE__} updating state - #{inspect new_state.data}"
# #     #TODO this is where the GUI should be triggered, not the othe way around
# #     #TODO need to update the GUI here?
# #     {:noreply, new_state}
# #   end

# #   # spin up a new process to do the handling...
# #   defp start_sub_task(state, module, function, args) do
# #   Task.Supervisor.start_child(
# #       find_supervisor_pid(state), # start the task under the Task.Supervisor specific to this Buffer
# #           module,
# #           function,
# #           [state, args])
# #   end
# # end
