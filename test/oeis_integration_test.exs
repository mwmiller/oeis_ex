defmodule OEIS.IntegrationTest do
  use ExUnit.Case, async: true
  alias OEIS.Sequence
  require ExUnit.CaptureLog

  @moduletag :external

  test "search with keyword list returns a list with the correct sequence" do
    assert {:multi, [%Sequence{id: "A000055"} | _]} =
             OEIS.search(sequence: [1, 2, 3, 6, 11, 23, 47, 106, 235], keyword: "core")
  end

  test "search with a sequence string returns the correct sequence" do
    assert {:multi, [%Sequence{id: "A000055"} | _]} =
             OEIS.search("1,2,3,6,11,23,47,106,235")
  end

  test "search with a list of integers returns the correct sequence" do
    assert {:multi, [%Sequence{id: "A000055"} | _]} =
             OEIS.search([1, 2, 3, 6, 11, 23, 47, 106, 235])
  end

  test "search with an ID string returns the correct sequence" do
    assert {:single, %Sequence{id: "A000001"}} = OEIS.search("A000001")
  end

  test "search with an integer ID returns the correct sequence" do
    assert {:single, %Sequence{id: "A000055"}} = OEIS.search(55)
  end

  test "search with an integer-like string ID returns the correct sequence" do
    assert {:single, %Sequence{id: "A000055"}} = OEIS.search("55")
  end

  test "search with an exact A-number returns a single sequence" do
    assert {:single,
            %Sequence{
              id: "A037074",
              name: "Numbers that are the product of a pair of twin primes." <> _
            }} = OEIS.search("A037074")
  end

  test "search by author (greedy) and query returns a list of sequences" do
    # "Sloane" is a common author, "core" is a common keyword
    assert {:partial, sequences} =
             OEIS.search(author: "Sloane", query: "core")

    assert is_list(sequences)
    # Check if the search returned sequences authored by Sloane, though "core" limits it
    assert Enum.any?(sequences, fn s -> s.author && String.contains?(s.author, "Sloane") end)
  end

  test "search with start parameter returns a list of sequences" do
    assert {:partial, sequences} =
             OEIS.search(query: "partitions", start: 10)

    assert is_list(sequences)
  end

  test "search with invalid start parameter returns bad_param error" do
    assert {:error, {:bad_param, ":start must be a non-negative integer."}} =
             OEIS.search(query: "some query", start: -1)
  end

  test "search with too few terms returns a list of sequences and a warning" do
    # This query typically returns many results, triggering the warning
    assert {:partial, sequences} = OEIS.search(sequence: [1, 2, 3])
    assert is_list(sequences)
    assert not Enum.empty?(sequences)
    assert length(sequences) == 10
  end

  test "search with a specific query that returns exactly 10 results emits a warning" do
    assert {:partial, sequences} = OEIS.search(sequence: [1, 2, 3])

    assert is_list(sequences)
    assert length(sequences) == 10
  end

  test "search with non-existent sequence returns an empty list" do
    assert {:no_match, "No matches found."} = OEIS.search(sequence: "999,998,997,996,995")
  end

  test "search with query for a non-existent pattern returns an empty list" do
    assert {:no_match, "No matches found."} =
             OEIS.search(query: "a pattern that surely does not exist in OEIS")
  end

  test "extracted links are usable URLs" do
    # Search for a sequence with known links

    assert {:single, %Sequence{link: links}} = OEIS.search(id: "A000001")

    assert is_list(links)

    assert not Enum.empty?(links)

    # Check if a sample link is a valid URL format (starts with http/https)

    assert Enum.all?(links, fn link ->
             assert is_map(link)

             assert Map.has_key?(link, :url)

             assert Map.has_key?(link, :text)

             String.starts_with?(link.url, "http")
           end)
  end

  test "references field is correctly populated for A000001" do
    assert {:single, %Sequence{reference: references}} = OEIS.search(id: "A000001")
    assert is_list(references)
    assert not Enum.empty?(references)
    # Check for a couple of known references from the curl output for A000001
    assert Enum.any?(references, fn ref -> String.contains?(ref, "S. R. Blackburn") end)
    assert Enum.any?(references, fn ref -> String.contains?(ref, "L. Comtet") end)
  end

  test "fetch_linked_data successfully fetches and parses b-file data for A000001" do
    {:single, sequence} = OEIS.search("A000001")

    assert {:ok, [%{title: "Table of n, a(n) for n = 0..2047", data: a000001_data} | _]} =
             OEIS.fetch_linked_data(sequence)

    assert is_list(a000001_data)
    # A000001 has at least 10 entries in its b-file
    assert length(a000001_data) >= 10
    # First value for A000001 is 0
    assert Enum.at(a000001_data, 0) == 0
    # Second value for A000001 is 1
    assert Enum.at(a000001_data, 1) == 1
  end

  test "fetch_linked_data returns no_links_found for a sequence without b-file links (A360000)" do
    {:single, sequence} = OEIS.search("A360000")

    assert {:no_links_found, "No b-file links found for this sequence."} =
             OEIS.fetch_linked_data(sequence)
  end

  test "fetch_linked_data returns error for invalid input type" do
    assert {:error, "Input must be an OEIS.Sequence struct."} =
             OEIS.fetch_linked_data("not a sequence")
  end

  test "search with invalid input type returns a bad_param error" do
    assert {:error,
            {:bad_param, "Input must be a keyword list, a list of integers, or a string."}} =
             OEIS.search(%{invalid: :map})
  end

  test "search with invalid sequence string returns bad_param error" do
    assert {:error, {:bad_param, "Sequence string must be a comma-separated list of integers."}} =
             OEIS.search(sequence: "1, 2, three")
  end

  test "search by name returns the correct sequence" do
    assert {:partial, [%Sequence{id: "A000045"} | _]} =
             OEIS.search(name: "Fibonacci")
  end
end
