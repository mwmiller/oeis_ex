defmodule OEIS do
  alias Jason
  alias OEIS.Sequence

  @moduledoc """
  A client for the On-Line Encyclopedia of Integer Sequences (OEIS).
  """

  @base_url "https://oeis.org"
  @max_sequence_terms 10

  @string_fields [
    :keyword,
    :comment,
    :ref,
    :link,
    :formula,
    :example,
    :name,
    :xref
  ]

  @doc """
  Searches the OEIS database.

  This function is the main entry point for querying the OEIS. It can be called
  with a keyword list of search parameters, a raw list of integers (treated as
  a sequence), or a raw string.

  When called with a string, it will be treated as an OEIS ID if it matches
  the `A` number format (e.g., `"A000055"`), otherwise it will be treated as a
  comma-separated sequence (e.g., `"1,2,3,4"`).

  On success, returns `{:single, sequence}` for an exact ID match, or `{:multi, list_of_sequences}` for other searches. `list_of_sequences` is a list of `OEIS.Sequence` structs. If no results are found, `{:no_match, "No matches found."}` is returned.

  If a query returns a full page of results (currently 10 sequences for general
  searches), it implies there might be more results available. In such cases,
  a `{:partial, list_of_sequences}` tuple is returned.

  ## Parameters

  When called with a keyword list, the following keys are accepted:

  * `:sequence` (list of integers or a comma-separated string): A list of terms
    in the sequence to search for. If the sequence has more than 10 terms, it will
    be automatically adjusted: leading 0s and 1s will be removed, and if it remains
    longer than 10 terms, it will be truncated to the first 10 terms, as per OEIS hints.
    * Example: `[1, 2, 3, 6, 11, 23]` or `"1,2,3,6,11,23"`
  * `:id` (string): An OEIS A-number to search for.
    * Example: `"A000055"`
  * `:keyword` (string): A keyword to filter results.
    * Example: `"core"`
  * `:author` (string): An author's name to filter results. The search is
    automatically made greedy by surrounding the name with `*`.
    * Example: `"Sloane"`
  * `:query` (string): A general query string for other search terms.
    * Example: `"number of partitions"`
  * `:start` (integer): The starting index for results, used for pagination.
    * Default is 0.

  ## Examples

      iex> OEIS.search("A000045")
      {:single, %OEIS.Sequence{id: "A000045", name: "Fibonacci numbers." <> _}}

      iex> OEIS.search([1, 2, 3, 5, 8])
      {:multi, [%OEIS.Sequence{id: "A000045", name: "Fibonacci numbers." <> _}]}

      iex> OEIS.search(query: "non-existent query")
      {:no_match, "No matches found."}

      iex> OEIS.search(author: "Sloane", keyword: "core", start: 10)
      {:partial, list_of_sequences}

      iex> {:partial, sequences} = OEIS.search(sequence: [1, 2, 3])
      iex> length(sequences)
      10

      # A broad query like "prime number" often returns no results from the JSON API,
      # which now translates to `{:no_match, "No matches found."}`. The OEIS JSON API
      # currently does not provide a distinct indicator for "too many results"
      # versus "no results" in its JSON response.
      iex> OEIS.search(query: "prime number")
      {:no_match, "No matches found."}
  """
  def search(opts) do
    case opts do
      num when is_integer(num) ->
        do_search(id: "A" <> String.pad_leading(to_string(num), 6, "0"))

      str when is_binary(str) ->
        handle_string_search(str)

      list when is_list(list) ->
        case Keyword.keyword?(list) do
          true -> do_search(list)
          false -> do_search(sequence: list)
        end

      _ ->
        {:error, {:bad_param, "Input must be a keyword list, a list of integers, or a string."}}
    end
  end

  @doc """
  Fetches and parses extra data associated with an OEIS sequence, returning extracted data.

  This function takes an `OEIS.Sequence` struct, identifies the single link pointing to
  an `oeis.org/.../b<A-number>.txt` file (which contains the extra data), fetches its content, and extracts
  the integer values from the second column of each line. The leading index column
  in these `.txt` files is ignored.

  Returns `{:extra_data, data}` on success, where `data` is a list of integers extracted
  from the linked extra data.
  Returns `{:no_links_found, message}` if no relevant extra data link is found in the sequence.
  Returns `{:no_match, message}` if an extra data link is found but no integer data can be extracted.
  Returns `{:error, reason}` if any HTTP request or parsing operation fails.

  ## Parameters
  * `sequence` (OEIS.Sequence): The OEIS sequence struct containing links.

  ## Examples
      iex> OEIS.search("A000001")
      ...> |> case do
      ...>   {:single, seq} -> OEIS.fetch_extra_data(seq)
      ...>   _ -> {:error, "Sequence not found"}
      ...> end
      {:extra_data, [0, 1, 1, 2, 1, 2, 2, 1, 5, 2, 2, ...]} # Example shortened
  """
  def fetch_extra_data(%Sequence{link: links}) do
    case Enum.find(links, &Map.get(&1, :extra_data, false)) do
      nil ->
        {:no_links_found, "No extra data link found for this sequence."}

      %{url: url, text: title} = link ->
        process_b_file_link(link, url, title)
    end
  end

  def fetch_extra_data(_other) do
    {:error, "Input must be an OEIS.Sequence struct."}
  end

  defp process_b_file_link(%{url: url, text: title}, _url, _title) do
    case fetch_and_parse_extra_data(url) do
      {:ok, data} ->
        case data do
          [] -> {:no_match, "No integer data extracted from extra data for link: #{title}"}
          # <--- Modified
          _ -> {:extra_data, data}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_and_parse_extra_data(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        parse_extra_data_content(body)

      {:ok, %{status: status, body: body}} ->
        {:error,
         {:http_error,
          "Failed to fetch extra data from #{url}: HTTP #{status} - #{inspect(body)}"}}

      {:error, reason} ->
        {:error, {:http_error, "Failed to fetch extra data from #{url}: #{inspect(reason)}"}}
    end
  end

  defp parse_extra_data_content(content) when is_binary(content) do
    lines = String.split(content, ~r/\r?\n/, trim: true)
    extracted_integers = Enum.flat_map(lines, &parse_extra_data_line/1)
    {:ok, extracted_integers}
  end

  defp parse_extra_data_line(line) do
    case String.split(line, ~r/\s+/, trim: true) do
      [_, second_col_str | _] ->
        case Integer.parse(second_col_str) do
          {integer, ""} -> [integer]
          # Not a valid integer, ignore
          _ -> []
        end

      # Line doesn't have at least two columns, ignore
      _ ->
        []
    end
  end

  defp handle_string_search(<<"A", _id_num::binary-size(6)>> = a_number) do
    do_search(id: a_number)
  end

  defp handle_string_search(str) do
    case Integer.parse(str) do
      {num, ""} ->
        do_search(id: "A" <> String.pad_leading(to_string(num), 6, "0"))

      # Not an integer, treat as sequence
      _ ->
        do_search(sequence: str)
    end
  end

  defp do_search(opts) do
    case Keyword.fetch(opts, :id) do
      {:ok, id} ->
        case make_id_request(id) do
          {:ok, decoded_json_body} -> handle_oeis_response(decoded_json_body)
          err -> err
        end

      # This is the general search branch

      :error ->
        with {:ok, query_params} <- build_query_string(opts),
             search_url = Path.join(@base_url, "/search"),
             {:ok, decoded_json_body} <- make_request(search_url, query_params) do
          handle_oeis_response(decoded_json_body)
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp make_id_request(id) do
    url = Path.join(@base_url, "#{id}?fmt=json")

    case Req.get(url) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        # body is already decoded by Req (could be nil, a map, or a list)
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, "HTTP Error: #{status} - #{inspect(body)}"}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp build_query_string(opts) do
    with {:ok, query_map} <- build_base_query_map(opts) do
      handle_start_param(query_map, Keyword.get(opts, :start))
    end
  end

  defp build_base_query_map(opts) do
    do_build_query_terms(opts, {:ok, []})
  end

  defp do_build_query_terms([], {:ok, acc_terms}) do
    case Enum.empty?(acc_terms) do
      true ->
        {:error,
         {:bad_param,
          "At least one of :sequence, :id, :keyword, :author, or :query must be provided."}}

      false ->
        q_value = Enum.join(acc_terms, " ")
        {:ok, %{q: q_value, fmt: "json"}}
    end
  end

  defp do_build_query_terms([{_key, nil} | tail], acc_status),
    do: do_build_query_terms(tail, acc_status)

  defp do_build_query_terms([head | tail], {:ok, acc_terms}) do
    {key, value} = head

    case key do
      # <--- Skip :start
      :start ->
        do_build_query_terms(tail, {:ok, acc_terms})

      _ ->
        case add_query_term(acc_terms, key, value) do
          {:ok, new_acc_terms} -> do_build_query_terms(tail, {:ok, new_acc_terms})
          {:error, _} = err -> err
        end
    end
  end

  defp do_build_query_terms([_head | _tail], {:error, _} = err), do: err
  defp do_build_query_terms([], {:error, _} = err), do: err

  defp handle_start_param(query_map, nil), do: {:ok, query_map}

  defp handle_start_param(query_map, start_param)
       when is_integer(start_param) and start_param >= 0 do
    {:ok, Map.put(query_map, :start, start_param)}
  end

  defp handle_start_param(_query_map, _),
    do: {:error, {:bad_param, ":start must be a non-negative integer."}}

  defp parse_integer_string(sequence_str) do
    integers_and_remains =
      sequence_str
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&Integer.parse/1)

    case Enum.all?(integers_and_remains, fn
           {int, rest} when is_integer(int) and rest == "" -> true
           _ -> false
         end) do
      true -> {:ok, Enum.map(integers_and_remains, fn {int, _rest} -> int end)}
      false -> {:error, :not_an_integer_list_string}
    end
  end

  defp add_query_term(acc_terms, :sequence, sequence) when is_list(sequence) do
    case Enum.all?(sequence, &is_integer/1) do
      true ->
        truncated_sequence = truncate_sequence_list(sequence)
        {:ok, [Enum.map_join(truncated_sequence, ",", &to_string/1) | acc_terms]}

      false ->
        {:error,
         {:bad_param,
          "Sequence must be a list of integers or a comma-separated string of integers."}}
    end
  end

  defp add_query_term(acc_terms, :sequence, sequence) when is_binary(sequence) do
    case parse_integer_string(sequence) do
      {:ok, int_list} ->
        truncated_sequence = truncate_sequence_list(int_list)
        {:ok, [Enum.join(truncated_sequence, ",") | acc_terms]}

      _ ->
        {:error, {:bad_param, "Sequence string must be a comma-separated list of integers."}}
    end
  end

  defp add_query_term(_acc_terms, :sequence, _),
    do:
      {:error,
       {:bad_param,
        "Sequence must be a list of integers or a comma-separated string of integers."}}

  defp add_query_term(acc_terms, :id, <<"A", _id_num::binary-size(6)>> = id) do
    {:ok, ["id:" <> id | acc_terms]}
  end

  defp add_query_term(_acc_terms, :id, _id),
    do:
      {:error,
       {:bad_param,
        "ID must be a string starting with 'A' and 7 characters long (e.g., 'A000001')."}}

  defp add_query_term(acc_terms, key, value) when key in @string_fields and is_binary(value) do
    {:ok, ["#{Atom.to_string(key)}:" <> value | acc_terms]}
  end

  defp add_query_term(_acc_terms, key, _value) when key in @string_fields do
    {:error, {:bad_param, "#{Atom.to_string(key)} must be a string."}}
  end

  defp add_query_term(acc_terms, :author, author) when is_binary(author) do
    {:ok, ["author:*" <> author <> "*" | acc_terms]}
  end

  defp add_query_term(_acc_terms, :author, _),
    do: {:error, {:bad_param, "Author must be a string."}}

  defp add_query_term(acc_terms, :query, query_str) when is_binary(query_str) do
    {:ok, [query_str | acc_terms]}
  end

  defp add_query_term(_acc_terms, :query, _),
    do: {:error, {:bad_param, "General query must be a string."}}

  # Catch-all for unsupported options

  defp add_query_term(_acc_terms, key, value),
    do:
      {:error, {:bad_param, "Unsupported option: #{inspect(key)} with value: #{inspect(value)}."}}

  defp truncate_sequence_list(list) do
    case length(list) <= @max_sequence_terms do
      true ->
        list

      false ->
        list
        |> Enum.drop_while(&(&1 in [0, 1]))
        |> case do
          [] -> list
          stripped -> stripped
        end
        |> Enum.take(@max_sequence_terms)
    end
  end

  defp make_request(url, query_params) do
    case Req.get(url, params: query_params) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        # body is already decoded by Req (could be nil, a map, or a list)
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, "HTTP Error: #{status} - #{inspect(body)}"}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp handle_oeis_response(nil), do: {:no_match, "No matches found."}

  # Case for when the OEIS API returns a list of results (general search).
  defp handle_oeis_response(results) when is_list(results) and length(results) == 10 do
    # Include the raw results if desired
    {:partial, Enum.map(results, &map_to_sequence/1)}
  end

  defp handle_oeis_response(results) when is_list(results) do
    case results do
      [] ->
        {:no_match, "No matches found."}

      _avail ->
        {:multi, Enum.map(results, &map_to_sequence/1)}
    end
  end

  # Case for when the OEIS API returns a single sequence object (map) for direct A-number lookups.
  defp handle_oeis_response(%{"number" => _, "data" => _} = single_result) do
    {:single, map_to_sequence(single_result)}
  end

  defp handle_oeis_response(other), do: {:error, {:unknown_response_format, other}}

  defp map_to_sequence(result) do
    data = Map.get(result, "data", "")
    {_ok, data_list} = parse_integer_string(data)

    created =
      with created_str when is_binary(created_str) <- Map.get(result, "created"),
           {:ok, dt, _} <- DateTime.from_iso8601(created_str) do
        dt
      else
        _ -> nil
      end

    time =
      with time_str when is_binary(time_str) <- Map.get(result, "time"),
           {:ok, dt, _} <- DateTime.from_iso8601(time_str) do
        dt
      else
        _ -> nil
      end

    %Sequence{
      id: "A" <> String.pad_leading(to_string(Map.get(result, "number")), 6, "0"),
      number: Map.get(result, "number"),
      name: Map.get(result, "name"),
      data: data_list,
      comment: Map.get(result, "comment"),
      reference: Map.get(result, "reference"),
      formula: Map.get(result, "formula"),
      example: Map.get(result, "example"),
      link: extract_links_from_result(result),
      author: extract_author(result),
      created: created,
      time: time
    }
  end

  defp extract_author(result) do
    author_regex = ~r/_([A-Za-z.\s]+?)_/
    comments = Map.get(result, "comment", [])
    references = Map.get(result, "reference", [])

    all_texts =
      case comments do
        list when is_list(list) -> list
        _ -> []
      end ++
        case references do
          list when is_list(list) -> list
          _ -> []
        end

    authors =
      Enum.flat_map(all_texts, fn text ->
        case Regex.run(author_regex, to_string(text)) do
          [_whole, author] -> [String.trim(author)]
          _ -> []
        end
      end)
      |> Enum.uniq()
      |> Enum.sort()

    case authors do
      [] -> nil
      _ -> Enum.join(authors, ", ")
    end
  end

  defp extract_links_from_result(result) do
    href_regex = ~r/href="([^"]*)">([^<]+)<\/a>/
    links = Map.get(result, "link", [])
    Enum.flat_map(links, &parse_link_string(&1, href_regex))
  end

  defp parse_link_string(link_str, href_regex) do
    case Regex.scan(href_regex, to_string(link_str)) do
      matches when matches != [] ->
        Enum.map(matches, fn [_, url, text] -> build_link_map(url, text) end)

      _ ->
        []
    end
  end

  defp build_link_map(url, text) do
    formatted_url = format_full_url(url)
    link_map = %{url: formatted_url, text: text}

    case String.match?(formatted_url, ~r"oeis\.org/A\d+/b\d+\.txt$") do
      true -> Map.put(link_map, :extra_data, true)
      false -> link_map
    end
  end

  defp format_full_url("/" <> _rest = url), do: "https://oeis.org" <> url
  defp format_full_url(url), do: url
end
