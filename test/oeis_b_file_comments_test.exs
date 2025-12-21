defmodule OEIS.BFileCommentsTest do
  use ExUnit.Case, async: true

  @tag :integration
  test "fetches and appends comments from b-file for A000105" do
    # specific sequence known to have comments in b-file
    {:single, seq} = OEIS.search("A000105")

    {:ok, updated_seq} = OEIS.fetch_more_terms(seq)

    b_file_comments = Enum.filter(updated_seq.comment, &String.starts_with?(&1, "[b-file"))

    refute Enum.empty?(b_file_comments)
    assert Enum.any?(b_file_comments, fn c -> String.contains?(c, "contributed by") end)
  end
end
