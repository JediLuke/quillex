defmodule QuillEx.API.Buffer do

   def new do
      IO.puts "MAKE NEW BUFFER"
   end
   
   def open do
      open("./README.md")
   end

   def open(file) do
      QuillEx.action({:open_file, file})
   end
end