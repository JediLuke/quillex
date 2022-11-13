defmodule QuillEx.Reducers.BufferReducer.Utils do

   # finds the active_buf by default
   def filter_active_buf(%{editor: %{buffers: buf_list, active_buf: active_buf}}) when not is_nil(active_buf) do
      find_buf(buf_list, active_buf)
   end

   def find_buf(%{editor: %{buffers: buf_list}}, buf_id) do
      find_buf(buf_list, buf_id)
   end

   def find_buf(buf_list, buf_id) when is_list(buf_list) and length(buf_list) >= 1 do
      [buffer = %{id: ^buf_id}] = buf_list |> Enum.filter(&(&1.id == buf_id))
      buffer
   end

   def update_active_buf(radix_state, changes) do
      active_buf = filter_active_buf(radix_state)
      update_buf(radix_state, active_buf, changes)
   end

   def update_buf(radix_state, %{id: old_buf_id}, changes) do
      update_buf(radix_state, old_buf_id, changes)
   end

   def update_buf(%{editor: %{buffers: buf_list}} = radix_state, {:buffer, _id} = old_buf_id, changes) do
      radix_state
      |> put_in([:editor, :buffers], buf_list |> Enum.map(fn
         %{id: ^old_buf_id} = old_buf ->
            QuillEx.Structs.Buffer.update(old_buf, changes)
         any_other_buffer ->
            any_other_buffer
      end))
   end

end