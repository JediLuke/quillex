defmodule Quillex.Highlight do
  @moduledoc """
  Token spans for syntax highlighting, computed with Makeup's pure-Elixir
  lexers and reduced to a handful of editor classes.

  A file's lexer is chosen by extension through `Makeup.Registry`; the
  `makeup_*` packages in mix.exs register their languages on start. Lexing
  a 2,400-line Elixir file takes ~25ms, so the store re-lexes whole
  documents (debounced) rather than tracking incremental edits.

  ## Classes

  Makeup's fine-grained token types collapse to classes the theme styles:

  - `:keyword` — `def`, `do`, `end`, `if`, `fn`…
  - `:definition` — module and function names
  - `:attribute` — `@moduledoc`, `@spec`…
  - `:comment`
  - `:doc` — multi-line strings (heredocs, docstrings)
  - `:string` — one-line strings, chars, sigils
  - `:number`

  Everything else (punctuation, operators, plain names, atoms) is unstyled.
  """

  @type span :: {start :: non_neg_integer(), stop :: non_neg_integer(), class :: atom()}
  @type lines :: %{pos_integer() => {String.t(), [span()]}}

  @doc "The Makeup lexer for a file path, from its extension(s), or nil."
  @spec lexer_for_path(Path.t() | nil) :: {module(), keyword()} | nil
  def lexer_for_path(nil), do: nil

  def lexer_for_path(path) when is_binary(path) do
    # "foo.html.eex" tries "html.eex" before "eex".
    path
    |> Path.basename()
    |> String.split(".")
    |> tl()
    |> suffixes()
    |> Enum.find_value(fn ext ->
      case Makeup.Registry.fetch_lexer_by_extension(ext) do
        {:ok, lexer_and_opts} -> lexer_and_opts
        :error -> nil
      end
    end)
  end

  defp suffixes([]), do: []
  defp suffixes([_ | rest] = parts), do: [Enum.join(parts, ".") | suffixes(rest)]

  @doc """
  Spans for every line of `lines` that has any, keyed by 1-based line number
  and carrying the line's text so a consumer can tell when they are stale.
  """
  @spec spans([String.t()], {module(), keyword()}) :: lines()
  def spans(lines, {lexer, opts}) when is_list(lines) do
    tokens = lexer.lex(Enum.join(lines, "\n"), opts)

    {by_line, _line, _col} =
      Enum.reduce(tokens, {%{}, 1, 0}, fn {type, _meta, value}, {acc, line, col} ->
        text = IO.chardata_to_string(value)
        parts = String.split(text, "\n")
        class = class_for(type, length(parts) > 1)
        place_parts(parts, class, acc, line, col)
      end)

    lines
    |> Enum.with_index(1)
    |> Enum.reduce(%{}, fn {text, n}, acc ->
      case Map.get(by_line, n) do
        nil -> acc
        spans -> Map.put(acc, n, {text, Enum.reverse(spans)})
      end
    end)
  end

  # Lay a token's newline-split parts onto consecutive lines.
  defp place_parts([part], class, acc, line, col) do
    len = String.length(part)
    {add_span(acc, line, col, col + len, class), line, col + len}
  end

  defp place_parts([part | rest], class, acc, line, col) do
    len = String.length(part)
    acc = add_span(acc, line, col, col + len, class)
    place_parts(rest, class, acc, line + 1, 0)
  end

  defp add_span(acc, _line, start, stop, class) when class == nil or stop <= start, do: acc

  defp add_span(acc, line, start, stop, class) do
    Map.update(acc, line, [{start, stop, class}], &[{start, stop, class} | &1])
  end

  @doc "Reduce a Makeup token type to an editor class (nil = unstyled)."
  def class_for(type, multiline?) do
    case Atom.to_string(type) do
      "keyword" <> _ -> :keyword
      "name_function" -> :definition
      "name_class" -> :definition
      "name_namespace" -> :definition
      "name_attribute" -> :attribute
      "name_decorator" -> :attribute
      "comment" <> _ -> :comment
      "string_symbol" -> nil
      "string_interpol" -> nil
      "string_escape" -> :string
      "string" <> _ -> if multiline?, do: :doc, else: :string
      "number" <> _ -> :number
      "generic_heading" -> :keyword
      "generic_subheading" -> :keyword
      "generic_strong" -> :keyword
      "generic_emph" -> :comment
      "generic_inserted" -> :string
      "generic_deleted" -> :comment
      _ -> nil
    end
  end
end
