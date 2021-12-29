defmodule QuillEx.API.Buffer do

   def new do
      QuillEx.action({:open_buffer, %{data: ""}})
   end

   def new(raw_text) when is_bitstring(raw_text) do
      QuillEx.action({:open_buffer, %{data: raw_text}})
   end

   @doc """
   Return the active Buffer.
   """ 
   def active_buf do
      QuillEx.RadixAgent.get().active_buf
   end

   @doc """
   Set which buffer is the active buffer.
   """ 
   def activate(buffer_ref) do
      QuillEx.action({:activate_buffer, buffer_ref})
   end

   @doc """
   Set which buffer is the active buffer.

   This function does the same thing as `activate/1`, it's just another
   entry point via the API, included for better DX (dev-experience).
   """ 
   def switch(buffer_ref) do
      QuillEx.action({:activate_buffer, buffer_ref})
   end
   
   @doc """
   List all the open buffers.
   """
   def list do
      QuillEx.RadixAgent.get().buffers
   end
   
   def open do
      open("./README.md")
   end

   def open(filepath) do
      QuillEx.action({:open_buffer, %{filepath: filepath}})
   end

   def find(search_term) do
      raise "cant find yet"
   end

   @doc """
   Return the contents of a buffer.
   """
   def read(buf) do
      [buf] = list() |> Enum.filter(& &1.id == buf)
      buf.data
   end

   def modify(buf) do
      raise "dont know how to modify a buffer yet"
      # ProcessRegistry.find!(buf) |> GenServer.call(:read)
   end

   def save(buf) do
      raise "dont know how to save a buffer yet"
      # ProcessRegistry.find!(buf) |> GenServer.call(:read)
   end

   def close do
      active_buf() |> close()
   end

   def close(buf) do
      QuillEx.action({:close_buffer, buf})
   end
  
end