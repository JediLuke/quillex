defmodule QuillEx.Structs.Buffer do
    alias QuillEx.Structs.Buffer.Cursor

    
    defstruct [
        id: nil,                # a unique id for referencing the buffer
        name: "unnamed",        # the name of the buffer that appears in the tab-bar
        data: nil,              # where the actual contents of the buffer is kept
        details: nil,           # where the file is saved, or came from
        cursors: [],            # a list of all the cursors in the buffer
        history: [],            # track all the modifications as we do them, for undo/redo purposes
        scroll_acc: {0,0},      # Where we keep track of how much we've scrolled the buffer around
        read_only?: false       # a flag which lets us know if it's a read-only buffer
    ]


    def new(%{id: {:buffer, name} = id}) do
        %__MODULE__{
            id: id,
            name: name,
            cursors: [Cursor.new(%{num: 1})]
        }
    end

    def update(%__MODULE__{} = old_buf, %{scroll_acc: new_scroll}) do
        old_buf |> Map.put(:scroll_acc, new_scroll)
    end

    def update(%__MODULE__{} = old_buf, %{data: text}) when is_bitstring(text) do
        old_buf |> Map.put(:data, text)
    end

    # NOTE - if we have more than 1 cursor, we need a more sophisticated update method...
    def update(%__MODULE__{cursors: [_old_cursor]} = old_buf, %{cursor: %Cursor{} = c}) do
        old_buf |> Map.put(:cursors, [c])
    end

    # NOTE - if we have more than 1 cursor, we need a more sophisticated update method...
    def update(%__MODULE__{cursors: [old_cursor]} = old_buf, %{cursor: %{line: _l, col: _c} = new_coords}) do
        c = Cursor.update(old_cursor, new_coords)
        old_buf |> Map.put(:cursors, [c])
    end
end