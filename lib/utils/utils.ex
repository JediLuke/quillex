defmodule QuillEx.Lib.Utils do
  # def register_process(%{uuid: buf_uuid}, mod) do
  #   # this will register the GUI widget the same way we register the actual Buffer process
  #   Registry.register(Quillex.BufferRegistry, {buf_uuid, mod}, nil)
  # end

  #    # these functions are used to cap scrolling
  #    def apply_floor({x, y}, {min_x, min_y}) do
  #     {max(x, min_x), max(y, min_y)}
  #    end

  #    def apply_ceil({x, y}, {max_x, max_y}) do
  #       {min(x, max_x), min(y, max_y)}
  #    end

  # end

  #   def random_string do
  #     # https://dev.to/diogoko/random-strings-in-elixir-e8i
  #     for _ <- 1..10, into: "", do: <<Enum.random('0123456789abcdef')>>
  #   end
end
