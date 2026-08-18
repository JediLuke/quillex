defmodule Quillex.Search.GlobTest do
  use ExUnit.Case, async: true

  alias Quillex.Search.Glob

  defp excluded?(path, field), do: Glob.any_match?(path, Glob.compile_all(field))

  test "a pattern with no separator matches at any depth" do
    assert excluded?("mix.lock", "*.lock")
    assert excluded?("deps/foo/mix.lock", "*.lock")
    refute excluded?("mix.exs", "*.lock")
  end

  test "a pattern with a separator is anchored to the root" do
    assert excluded?("test/support/fixture.ex", "test/**")
    refute excluded?("lib/test/thing.ex", "test/**")
  end

  test "** spans separators, * does not" do
    assert excluded?("a/b/c/vendor/x.js", "**/vendor/**")
    assert excluded?("vendor/x.js", "**/vendor/**")
    refute excluded?("lib/a/b.ex", "lib/*.ex")
    assert excluded?("lib/b.ex", "lib/*.ex")
  end

  test "? matches one character inside a segment" do
    assert excluded?("a1.txt", "a?.txt")
    refute excluded?("a/1.txt", "a?.txt")
  end

  test "regex metacharacters in a pattern are literal" do
    assert excluded?("a+b.ex", "a+b.ex")
    refute excluded?("aab.ex", "a+b.ex")
  end

  test "a field holds several patterns, separated by spaces or commas" do
    assert Glob.split("**/deps/** *.lock, test/**") ==
             ["**/deps/**", "*.lock", "test/**"]

    assert excluded?("deps/x/y.ex", "**/deps/** *.lock")
    assert excluded?("mix.lock", "**/deps/** *.lock")
  end

  # The field is edited a character at a time; a pattern mid-typing must not
  # take the whole search down with it.
  test "compile_all drops patterns that will not compile and keeps the rest" do
    huge = String.duplicate("*", 2_000)
    regexes = Glob.compile_all("lib/** " <> huge)
    assert length(regexes) >= 1
    assert Glob.any_match?("lib/a.ex", regexes)
  end

  test "an empty field excludes nothing" do
    assert Glob.compile_all("") == []
    refute Glob.any_match?("anything", [])
  end
end
