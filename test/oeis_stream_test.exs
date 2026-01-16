defmodule OEIS.StreamTest do
  use ExUnit.Case, async: true
  alias OEIS.Sequence

  @moduletag :external

  test "search with stream: true returns a stream that yields results" do
    stream = OEIS.search(query: "partitions", stream: true)
    assert is_function(stream)

    results = Enum.take(stream, 15)
    assert length(results) == 15
    assert Enum.all?(results, fn s -> match?(%Sequence{}, s) end)
    # They should be unique IDs
    ids = Enum.map(results, & &1.id)
    assert length(Enum.uniq(ids)) == 15
  end

  test "streaming a single ID match" do
    stream = OEIS.search("A000045", stream: true)
    results = Enum.to_list(stream)
    assert [%Sequence{id: "A000045"}] = results
  end

  test "streaming no match" do
    stream = OEIS.search("asdfasdfasdfasdf", stream: true)
    results = Enum.to_list(stream)
    assert [] == results
  end

  test "streaming with start parameter" do
    # Skip first 5
    stream = OEIS.search(query: "partitions", stream: true, start: 5)
    results = Enum.take(stream, 10)
    assert length(results) == 10

    # Verify it skip some
    stream_full = OEIS.search(query: "partitions", stream: true)
    results_full = Enum.take(stream_full, 15)

    assert Enum.at(results, 0).id == Enum.at(results_full, 5).id
  end
end
