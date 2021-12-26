defmodule QuillEx.Utils.HoverUtils do
    
    # https://hexdocs.pm/scenic/0.11.0-beta.0/Scenic.Graph.html#bounds/1
    # def inside?({x, y}, {left, right, top, bottom} = _bounds) do
        def inside?({x, y}, {left, bottom, right, top} = _bounds) do #TODO update the docs in Scenic itself
        # remember, if y > top, if top is 100 cursor might be 120 -> in the box ??
        # top <= y and y <= bottom and left <= x and x <= right
        bottom <= y and y <= top and left <= x and x <= right
    end

end