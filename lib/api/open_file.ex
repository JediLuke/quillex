defmodule QuillEx.API.OpenFile do
    
    @readme "./README.md"

    def readme do
        {:ok, file_contents} = File.read(@readme)
        GenServer.call(QuillEx.StageManager, {:open, %{file: @readme, text: file_contents}})
    end
end