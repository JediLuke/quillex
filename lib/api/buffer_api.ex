defmodule QuillEx.API.Buffer do

   def new do
      QuillEx.action({:open_buffer, %{data: ""}})
   end
   
   def open do
      open("./README.md")
   end

   def open(filepath) do
      QuillEx.action({:open_buffer, %{filepath: filepath}})
   end

   def activate(buffer_ref) do
      QuillEx.action({:activate_buffer, buffer_ref})
   end
end