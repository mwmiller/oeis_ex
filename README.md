# OEIS.ex

An Elixir client for the On-Line Encyclopedia of Integer Sequences (OEIS).

This library provides a convenient way to search the OEIS database for integer sequences.

## Installation

Add `oeis` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:oeis, "~> 0.6.0"}
  ]
end
```

Then, run `mix deps.get` to fetch the new dependency.

## Usage

The primary function is `OEIS.search/2`. It can be called with a keyword list,
a list of integers, or a string.

### Searching

`OEIS.search/2` returns:
* `{:single, %OEIS.Sequence{}}` for an exact ID match.
* `{:multi, [%OEIS.Sequence{}, ...]}` for search results with 1-9 matches.
* `{:partial, [%OEIS.Sequence{}, ...]}` when exactly 10 results are returned (indicating potential pagination).
* `{:no_match, "No matches found."}` when no results are found.

```elixir
# Search with a keyword list
iex> OEIS.search(sequence: [1, 2, 3, 6, 11, 23], keyword: "core")
{:multi, [%OEIS.Sequence{id: "A000055", ...}]}

# Search with an ID string (A-number)
iex> OEIS.search("A000045")
{:single, %OEIS.Sequence{id: "A000045", name: "Fibonacci numbers..."}}

# Search with a general string query
iex> OEIS.search("Fibonacci")
{:partial, [%OEIS.Sequence{id: "A000045", ...}, ...]}

# Search by author (greedy) and general query
iex> OEIS.search(author: "Sloane", query: "partitions")
{:partial, [%OEIS.Sequence{...}, ...]}
```

### Advanced Features

#### Fetching More Terms
OEIS sequences often have limited terms in the primary record. `OEIS.fetch_more_terms/2` fetches the full "b-file" containing many more terms.

```elixir
iex> {:single, seq} = OEIS.search("A000001")
iex> {:ok, updated_seq} = OEIS.fetch_more_terms(seq)
# updated_seq.data now contains all terms from the b-file
```

#### Fetching Related Sequences
`OEIS.fetch_xrefs/2` extracts OEIS IDs from the cross-references field and fetches the full sequence definitions in parallel.

```elixir
iex> {:single, seq} = OEIS.search("A000045")
iex> related = OEIS.fetch_xrefs(seq, max_concurrency: 5)
# related is a list of OEIS.Sequence structs for Lucas numbers, etc.
```

#### Enumerable Sequences
`OEIS.Sequence` implements the `Enumerable` protocol, allowing you to iterate over its `data` directly.

```elixir
iex> {:single, seq} = OEIS.search("A000045")
iex> Enum.take(seq, 5)
[0, 1, 1, 2, 3]
```

### Standardized Options

Most functions accept a standard set of options:
* `:timeout` (integer): Request timeout in milliseconds (default: 15,000).
* `:max_concurrency` (integer): Concurrency limit for parallel tasks (default: 5).
* `:may_truncate` (boolean): Whether to truncate long sequences in search (default: true).
* `:respect_sign` (boolean): Whether search should respect sequence signs (default: true).

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/oeis>.
