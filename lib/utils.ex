defmodule QuillEx.Utils do
  alias Scenic.ViewPort
    
  def vp_width(vp) do
    {:ok, %ViewPort.Status{size: {w, _h}} = viewport} = ViewPort.info(vp)
    # make a small adjustment, make it 1 pixel wider
    # Scenic doesn't paint all the way to the right for some reason...
    w+1
  end

  def vp_height(vp) do
    {:ok, %ViewPort.Status{size: {_w, h}} = viewport} = ViewPort.info(vp)
    h
  end
end