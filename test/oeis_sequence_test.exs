defmodule OEIS.SequenceTest do
  use ExUnit.Case, async: true
  alias OEIS.Sequence

  describe "Enumerable implementation" do
    setup do
      seq = %Sequence{
        id: "A000045",
        data: [0, 1, 1, 2, 3, 5, 8]
      }

      {:ok, seq: seq}
    end

    test "Enum.count/1", %{seq: seq} do
      assert Enum.count(seq) == 7
    end

    test "Enum.member?/2", %{seq: seq} do
      assert Enum.member?(seq, 5) == true
      assert Enum.member?(seq, 10) == false
    end

    test "Enum.reduce/3", %{seq: seq} do
      assert Enum.reduce(seq, 0, &(&1 + &2)) == 20
    end

    test "Enum.to_list/1", %{seq: seq} do
      assert Enum.to_list(seq) == [0, 1, 1, 2, 3, 5, 8]
    end

    test "Enum.at/2", %{seq: seq} do
      assert Enum.at(seq, 0) == 0
      assert Enum.at(seq, 5) == 5
    end
  end
end
