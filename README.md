# OEIS.ex

An Elixir client for the On-Line Encyclopedia of Integer Sequences (OEIS).

This library provides a convenient way to search the OEIS database for integer sequences.

## Installation

Add `oeis` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:oeis, "~> 0.1.0"}
  ]
end
```

Then, run `mix deps.get` to fetch the new dependency.

## Usage

The primary function is `OEIS.search/1`. It can be called with a keyword list,
a list of integers, or a string.

When called with a string, it will be treated as an OEIS ID if it matches
the `A` number format (e.g., `"A000055"`), otherwise it will be treated as a
comma-separated sequence (e.g., `"1,2,3,4"`).

```elixir
# Search with a keyword list
iex> {:ok, [%OEIS.Sequence{id: "A000045", name: "Fibonacci numbers." <> _} | _]} =
...> OEIS.search(sequence: [1,2,3,5,8], keyword: "core")
{:ok, [%OEIS.Sequence{...}]}

# Search with a list of integers
iex> {:ok, [%OEIS.Sequence{id: "A000045", name: "Fibonacci numbers." <> _} | _]} =
...> OEIS.search([1,2,3,5,8])
{:ok, [%OEIS.Sequence{...}]}

# Search with a sequence string
iex> {:ok, [%OEIS.Sequence{id: "A000045", name: "Fibonacci numbers." <> _} | _]} =
...> OEIS.search("1,2,3,5,8")
{:ok, [%OEIS.Sequence{...}]}

# Search with an ID string
iex> {:ok, [%OEIS.Sequence{id: "A000001", name: "Number of groups of order n." <> _} | _]} =
...> OEIS.search("A000001")
{:ok, [%OEIS.Sequence{...}]}

# Search by author (greedy) and general query
iex> {:ok, [%OEIS.Sequence{id: "A000040", name: "The prime numbers." <> _} | _]} =
...> OEIS.search(author: "Euler", query: "prime numbers")
{:ok, [%OEIS.Sequence{...}]}

# Links are extracted to a list of URLs
iex> {:ok, [%OEIS.Sequence{link: ["https://oeis.org/A000001/b000001.txt", "https://www.jstor.org/stable/1967981", ...]}]} =
...> OEIS.search(id: "A000001")
{:ok, [%OEIS.Sequence{...}]}
```

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/oeis>.
