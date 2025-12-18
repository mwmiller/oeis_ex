defmodule OEIS.Sequence do
  @moduledoc """
  Represents a sequence from the On-Line Encyclopedia of Integer Sequences.

  ## Fields

  * `:id` - The OEIS A-number (e.g., "A000045").
  * `:number` - The integer part of the ID (e.g., 45).
  * `:name` - The name or description of the sequence.
  * `:data` - A list of integers representing the sequence data.
  * `:comment` - A list of comments associated with the sequence.
  * `:reference` - A list of bibliographic references.
  * `:formula` - A list of formulas describing the sequence.
  * `:example` - A list of examples.
  * `:link` - A list of links (maps with :url and :text keys).
  * `:xref` - A list of cross-references to other sequences.
  * `:author` - The author(s) of the sequence.
  * `:created` - The creation timestamp (DateTime).
  * `:time` - The last modification timestamp (DateTime).
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
    :xref,
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
