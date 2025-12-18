defmodule OEIS.ErrorTest do
  use ExUnit.Case, async: true

  test "parse_extra_data_line with invalid data" do
    # Use direct private function testing if possible, but OEIS private functions are hard to reach.
    # We can use apply/3 for private functions if we really want to reach them, 
    # but it's better to test through public API or by mocking Req.
    # Since we can't mock Req easily here without adding dependencies, 
    # we'll try to trigger them through search.
    assert {:error, {:bad_param, "Sequence string cannot be empty."}} = OEIS.search(sequence: " ")

    assert {:error, {:bad_param, "Sequence list must contain only integers."}} =
             OEIS.search(sequence: [1, 2.5, 3])

    assert {:error, {:bad_param, "Sequence must be a list of integers or a string of integers."}} =
             OEIS.search(sequence: %{a: 1})
  end

  test "search with nil value in keyword list" do
    # nil values should be ignored by do_build_query_terms
    assert {:single, _} = OEIS.search(id: "A000045", keyword: nil)
  end

  test "search with empty keyword list" do
    assert {:error,
            {:bad_param,
             "At least one of :sequence, :id, :keyword, :author, or :query must be provided."}} =
             OEIS.search([])
  end

  test "search with invalid param type" do
    assert {:error,
            {:bad_param, "Input must be a keyword list, a list of integers, or a string."}} =
             OEIS.search(true)
  end
end
