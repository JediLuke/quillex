defmodule QuillEx.API.Buffer do
   
   def open do
      open("./README.md")
   end

   def open(file) do
      QuillEx.action({:open_file, file})
   end
end