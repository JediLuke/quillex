defmodule QuillEx.Handlers.BufferActions do
    alias QuillEx.Structs.Radix
    require Logger

    #NOTE: Our goal is to update the Radix state with the new buffer
    #      - that change will send out msgs to the GUI to make updates
    
    # match on this case, but pass it through, just to save on code-clutter
    def calc_radix_change(%Radix{} = r, {:action, a}) do
        Logger.debug "-- BufferAction -- #{inspect a}..."
        calc_radix_change(r, a)
    end


    def calc_radix_change(%{buffers: buf_list} = radix, {:open_buffer, new_buf}) do
        num_buffers = Enum.count(buf_list)
        #TODO make this a struct?
        new_buffer_id = "untitled_" <> Integer.to_string(num_buffers+1) <> ".txt"
        #TODO keep track of the active buffer...
        new_buffer_list = buf_list ++ [new_buf |> Map.merge(%{id: new_buffer_id})]
        {:ok, radix |> Map.put(:buffers, new_buffer_list)}
    end
end