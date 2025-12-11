defmodule OEIS.Sequence do
  @moduledoc """
  Represents a sequence from the On-Line Encyclopedia of Integer Sequences.
  """
  defstruct [
    :id,
    :number,
    :name,
    :data,
    :comment,
    :reference,
    :formula,
    :example,
    :link,
    :author,
    :created,
    :time
  ]

  defimpl Enumerable do
    def count(%OEIS.Sequence{data: data}) do
      {:ok, length(data)}
    end

    def member?(%OEIS.Sequence{data: data}, element) do
      {:ok, Enum.member?(data, element)}
    end

    def reduce(%OEIS.Sequence{data: data}, acc, fun) do
      Enum.reduce(data, acc, fun)
    end

    def slice(_s) do
      {:error, :not_available}
    end
  end
end
