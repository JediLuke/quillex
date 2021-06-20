defmodule QuillEx.ScenicComponent.EmeraldTablet do
   use Scenic.Component, has_children: true


   def init([a|_rest] = data, opts) when is_bitstring(a) do # a list of strings
      id      = opts[:id]
      styles  = opts[:styles]
      width   = styles[:width]  || raise "need a width"
      height  = styles[:height] || raise "need a height"
      margin  = 0
      padding = p = 20
      window_bow = {width, height}
      text_box   = {width-(2*padding), height-(2*padding)} # padding applies to top and bottom / both sides

      init_graph =
         Scenic.Graph.build(scissor: window_bow)
         |> Scenic.Primitives.rect(text_box, t: {p, p}, fill: :green, stroke: {2, :yellow})

      init_state = %{
         id: id,
         graph: init_graph,
         width: width,
         height: height,
         lines: data,
         cursor: {1,1},
         focused: false,
         opts: opts
      }

      {:ok, init_state, push: init_state.graph}
   end




   @doc false
   @impl Scenic.Component
   def verify(data) do
      # verify/1 must be implemented by a Scenic.Component... so we're forced to do it
      {:ok, data}
   end
   def verify(_), do: :invalid_data

   @doc false
   @impl Scenic.Component
   def info(data) do
      # this is called by Scenic if we don't pass in correct params...
      # I never use it but we have to implement it so here it is
      raise "Failed to initialize #{__MODULE__} due to invalid params. Received: #{inspect data}"
   end
end