defmodule QuillEx.API.Buffer do

   def new do
      QuillEx.action({:open_buffer, %{data: ""}})
   end
   
   def open do
      open("./README.md")
   end

   def open(file) do
      QuillEx.action({:open_file, file})
   end
end