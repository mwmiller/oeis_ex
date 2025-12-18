defmodule OEIS.SearchFieldsTest do
  use ExUnit.Case, async: true

  @moduletag :external

  test "search with keyword" do
    assert {:partial, _} = OEIS.search(keyword: "core")
  end

  test "search with comment" do
    # Just verify it doesn't error out and sends the query
    assert {:no_match, _} = OEIS.search(comment: "non-existent-comment-search-string")
  end

  test "search with ref (bibliographic reference)" do
    assert {:no_match, _} = OEIS.search(ref: "non-existent-ref")
  end

  test "search with link" do
    assert {:no_match, _} = OEIS.search(link: "non-existent-link")
  end

  test "search with formula" do
    assert {:no_match, _} = OEIS.search(formula: "non-existent-formula")
  end

  test "search with example" do
    assert {:no_match, _} = OEIS.search(example: "non-existent-example")
  end

  test "search with name" do
    assert {:partial, _} = OEIS.search(name: "Fibonacci")
  end

  test "search with xref" do
    assert {:no_match, _} = OEIS.search(xref: "non-existent-xref")
  end

  test "search with invalid author (not a string)" do
    assert {:error, {:bad_param, "Author must be a string."}} = OEIS.search(author: 123)
  end

  test "search with invalid string field (not a string)" do
    assert {:error, {:bad_param, "keyword must be a string."}} = OEIS.search(keyword: 123)
  end

  test "search with unsupported option" do
    assert {:error, {:bad_param, "Unsupported option: :invalid with value: :value."}} =
             OEIS.search(invalid: :value)
  end

  test "search with list containing non-integers" do
    assert {:error, {:bad_param, "Sequence list must contain only integers."}} =
             OEIS.search(sequence: [1, "two", 3])
  end
end
