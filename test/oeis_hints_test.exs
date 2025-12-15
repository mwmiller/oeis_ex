defmodule OEIS.HintsTest do
  use ExUnit.Case, async: true
  alias OEIS.Sequence

  @moduletag :external

  test "search with space-separated sequence string" do
    # 1 2 3 6 11 23 matches A000055
    {status, results} = OEIS.search("1 2 3 6 11 23")
    assert status in [:multi, :partial]
    assert match?([%Sequence{id: "A000055"} | _], results)
  end

  test "search with mixed comma and space separated string" do
    {status, results} = OEIS.search("1, 2 3, 6 11, 23")
    assert status in [:multi, :partial]
    assert match?([%Sequence{id: "A000055"} | _], results)
  end

  test "search with :subseq parameter" do
    # subseq: matches numbers in order
    {status, _results} = OEIS.search(subseq: "1,2,3,5,8")
    assert status in [:multi, :partial]
  end

  test "truncation to 6 terms works" do
    # 7 terms: 1, 2, 3, 6, 11, 23, 47 -> should be truncated to 6
    # If we provide enough terms that usually match A000055, checking if it still returns valid results
    # is a proxy for ensuring the query wasn't malformed by truncation logic.
    long_seq = [1, 2, 3, 6, 11, 23, 47, 106]
    {status, sequences} = OEIS.search(long_seq)
    assert status in [:multi, :partial]
    assert Enum.any?(sequences, fn s -> s.id == "A000055" end)
  end
end
