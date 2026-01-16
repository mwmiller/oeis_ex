# OEIS Usage Rules

## Searching for Sequences

- Use `OEIS.search/2` for all searches.
- It returns `{:single, sequence}`, `{:multi, [sequences]}`, `{:partial, [sequences]}`, or `{:no_match, message}`.
- ALWAYS handle all four possible return values from `OEIS.search/2`.
- Prefer passing a list of integers for term searches: `OEIS.search([1, 2, 3])`.
- Use `stream: true` in options to get an Elixir `Stream` for results, which is useful for large result sets.

## Sequence Data

- `OEIS.Sequence` structs implement `Enumerable`, so you can use `Enum` functions directly on them to iterate over the sequence terms.
- Use `OEIS.fetch_more_terms/1` to get more terms from the b-file if the initial `data` is insufficient.

## Concurrency

- Use `OEIS.fetch_xrefs/2` to fetch referenced sequences concurrently.
- Respect the `:max_concurrency` option (default: 5) to avoid overwhelming the OEIS servers.

## Field Access

- Sequence IDs are always in the format "A000000" (padded to 6 digits).
- The `:data` field contains the terms available from the main OEIS page (usually ~40-50 terms).
- For more terms, you MUST call `OEIS.fetch_more_terms/1`.
