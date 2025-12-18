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

  ## Enumerable

  `OEIS.Sequence` implements the `Enumerable` protocol, which allows you to iterate
  over its sequence `:data` directly using the `Enum` module.

  ```elixir
  iex> {:single, seq} = OEIS.search("A000045")
  iex> Enum.take(seq, 5)
  [0, 1, 1, 2, 3]
  ```
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
      Enumerable.reduce(data, acc, fun)
    end

    def slice(_s) do
      {:error, __MODULE__}
    end
  end
end
