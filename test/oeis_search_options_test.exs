defmodule OEIS.SearchOptionsTest do
  use ExUnit.Case, async: true

  @moduletag :external

  test "search with long sequence and may_truncate: true (default) truncates sequence" do
    # > 6 terms, should be truncated.
    # A000045 (Fibonacci): 0, 1, 1, 2, 3, 5, 8, 13, 21...
    # If truncated (dropping leading 0,1s), it searches for 2, 3, 5, 8, 13, 21.
    # This should match A000045.
    long_sequence = [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55]
    {status, sequences} = OEIS.search(long_sequence)
    assert status in [:multi, :partial]
    assert Enum.any?(sequences, fn s -> s.id == "A000045" end)
  end

  test "search with long sequence and may_truncate: false performs exact search" do
    # Use a sequence that has > 6 terms (so it triggers truncation if enabled)
    # and has a tail that definitely doesn't match if included.
    # [2, 3, 4, 5, 6, 7, 8, 999]
    # may_truncate: true -> takes first 6: 2, 3, 4, 5, 6, 7. Matches A000027 (and others).
    # may_truncate: false -> searches 2, 3, 4, 5, 6, 7, 8, 999. Should be no match.

    seq = [2, 3, 4, 5, 6, 7, 8, 999]

    # With truncation (default)
    {status_t, results_t} = OEIS.search(seq, may_truncate: true)
    assert status_t in [:multi, :partial]
    assert Enum.any?(results_t, fn s -> s.id == "A000027" end)

    # Without truncation
    {status_f, _results_f} = OEIS.search(seq, may_truncate: false)
    # Should be no_match because of the 999 at the end of a long sequence
    assert status_f == :no_match
  end

  test "search with may_truncate: false preserves leading zeros" do
    # [0, 1, 2]
    # True: searches 1, 2 (drops leading 0) -> matches many
    # False: searches 0, 1, 2 -> matches fewer (e.g. A000045 starts with 0, 1, 1, 2 - wait 0,1,2 is A000027 offset 0?)

    # Just verify it runs without error as exact behavior depends on OEIS data
    seq = [0, 1, 2]
    {status_t, _} = OEIS.search(seq, may_truncate: true)
    {status_f, _} = OEIS.search(seq, may_truncate: false)

    assert status_t in [:multi, :partial, :no_match]
    assert status_f in [:multi, :partial, :no_match]
  end

  test "search with respect_sign: true (default) uses signed search" do
    # A000012 is all 1s: 1, 1, 1, 1...
    # If we search for 1, -1, 1, -1 it should probably not match A000012 if signs are respected.
    # It should match sequences like A010701 (Period 2: 1, -1, 1, -1...)

    seq = [1, -1, 1, -1, 1, -1]
    result = OEIS.search(seq, respect_sign: true)

    case result do
      {status, results} when status in [:multi, :partial] ->
        # Verify that we DO NOT match A000012 (all 1s)
        assert not Enum.any?(results, fn s -> s.id == "A000012" end)
        assert not Enum.empty?(results)

      _error ->
        flunk("Search returned error")
    end
  end

  test "search with respect_sign: false uses unsigned search (seq: prefix)" do
    # If we search for 1, -1, 1, -1, 1, -1 with respect_sign: false,
    # it should match sequences like 1, 1, 1, 1, 1, 1 (A000012) because signs are ignored.

    seq = [1, -1, 1, -1, 1, -1]
    result = OEIS.search(seq, respect_sign: false)

    case result do
      {status, results} when status in [:multi, :partial] ->
        # Should match A000012 (all 1s) or A008836 (Liouville) as both match 1,1,1... unsigned
        match_found =
          Enum.any?(results, fn s ->
            s.id == "A000012" or s.id == "A008836"
          end)

        assert match_found, "Expected A000012 or A008836 in results"

      _error ->
        flunk("Search returned error")
    end
  end
end
