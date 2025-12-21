defmodule OEIS do
  @moduledoc """
  A client for the On-Line Encyclopedia of Integer Sequences (OEIS).
  """

  alias OEIS.Sequence

  @base_url "https://oeis.org"
  @max_sequence_terms 6

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
  Searches the OEIS database for sequences.

  The first argument can be:
  * A string ID (e.g., `"A000055"`).
  * A list of integers (e.g., `[1, 2, 3, 5, 8]`).
  * A string of integers (e.g., `"1, 2, 3, 5, 8"` or `"1 2 3 5 8"`).
  * A keyword list of search parameters (see below).

  ## Options

  * `:may_truncate` (boolean): If `true` (default), sequences longer than 6 terms are truncated and leading 0s/1s removed.
  * `:respect_sign` (boolean): If `true` (default), respects signs. If `false`, ignores signs.
  * `:timeout` (integer): Request timeout in milliseconds (default: 15,000).
  * `:max_concurrency` (integer): Limit for parallel tasks (default: 5).
  * `:start` (integer): Starting index for results (default: 0).

  ## Parameters (Keyword List)

  * `:sequence` (list/string): Terms to search for.
  * `:id` (string): OEIS A-number.
  * `:keyword` (string): Filter keyword (e.g., `"core"`).
  * `:author` (string): Author name (automatically wildcards: `*name*`).
  * `:query` (string): General query string.

  ## Returns

  * `{:single, sequence}`: Exact ID match.
  * `{:multi, [sequence]}`: Multiple matches found.
  * `{:partial, [sequence]}`: Partial results (more likely available).
  * `{:no_match, message}`: No results found.

  ## Examples

      iex> OEIS.search("A000045")
      {:single, %OEIS.Sequence{id: "A000045", ...}}

      iex> OEIS.search([1, 2, 3, 5, 8])
      {:multi, [%OEIS.Sequence{id: "A000045", ...}]}

      iex> OEIS.search(author: "Sloane", keyword: "core", start: 10)
      {:partial, [...]}
  """
  def search(query, options \\ [])

  def search(num, options) when is_integer(num) do
    do_search([id: "A" <> String.pad_leading(to_string(num), 6, "0")], options)
  end

  def search(str, options) when is_binary(str) do
    handle_string_search(str, options)
  end

  def search(list, options) when is_list(list) do
    case Keyword.keyword?(list) do
      true -> do_search(list, options)
      false -> do_search([sequence: list], options)
    end
  end

  def search(_other, _options) do
    {:error, {:bad_param, "Input must be a keyword list, a list of integers, or a string."}}
  end

  @default_options [
    may_truncate: true,
    respect_sign: true,
    max_concurrency: 5,
    timeout: 15_000
  ]

  defp ensure_options(opts) do
    Keyword.merge(@default_options, opts)
  end

  @doc """
  Fetches extended sequence terms from the associated b-file.

  Parses the linked b-file (e.g., `b000001.txt`) to extract additional terms, replacing the existing `data` field.

  ## Options

  * `:timeout` (integer): Request timeout in milliseconds (default: 15,000).

  ## Returns

  * `{:ok, updated_sequence}`: Success.
  * `{:error, %{original_sequence: seq, message: msg}}`: Failure.

  ## Examples

      iex> {:single, seq} = OEIS.search("A000001")
      iex> {:ok, updated} = OEIS.fetch_more_terms(seq)
  """
  def fetch_more_terms(sequence, options \\ [])

  def fetch_more_terms(%OEIS.Sequence{} = original_sequence, options) do
    opts = ensure_options(options)

    case Enum.find(original_sequence.link, &Map.get(&1, :extra_data, false)) do
      nil ->
        {:error,
         %{
           original_sequence: original_sequence,
           message: "No extra data link found for this sequence."
         }}

      %{url: url, text: title} = link ->
        case process_b_file_link(link, url, title, opts) do
          {:extra_data, data} ->
            {:ok, %{original_sequence | data: data}}

          {:no_match, message} ->
            {:error, %{original_sequence: original_sequence, message: message}}

          {:error, reason} ->
            {:error, %{original_sequence: original_sequence, message: reason}}
        end
    end
  end

  def fetch_more_terms(_other, _options) do
    {:error, %{message: "Input must be an OEIS.Sequence struct."}}
  end

  @doc """
  Fetches sequences referenced in the `xref` field concurrently.

  ## Options

  * `:timeout` (integer): Request timeout in milliseconds (default: 15,000).
  * `:max_concurrency` (integer): Concurrency limit for parallel tasks (default: 5).

  ## Returns

  * `[sequence]`: List of successfully fetched `OEIS.Sequence` structs.

  ## Examples

      iex> {:single, seq} = OEIS.search("A000045")
      iex> refs = OEIS.fetch_xrefs(seq)
  """
  def fetch_xrefs(sequence, options \\ [])

  def fetch_xrefs(%OEIS.Sequence{xref: xref}, options) do
    opts = ensure_options(options)
    max_concurrency = opts[:max_concurrency]
    timeout = opts[:timeout]

    xref
    |> extract_xref_ids()
    |> Task.async_stream(
      fn id ->
        case search(id) do
          {:single, seq} -> seq
          _ -> nil
        end
      end,
      max_concurrency: max_concurrency,
      timeout: timeout
    )
    |> Enum.map(fn
      {:ok, result} -> result
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  def fetch_xrefs(_other, _options) do
    {:error, %{message: "Input must be an OEIS.Sequence struct."}}
  end

  defp process_b_file_link(%{url: url, text: title}, _url, _title, opts) do
    case fetch_and_parse_extra_data(url, opts) do
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

  defp fetch_and_parse_extra_data(url, opts) do
    req_opts = [receive_timeout: opts[:timeout]]

    case Req.get(url, req_opts) do
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

  defp handle_string_search(<<"A", _id_num::binary-size(6)>> = a_number, options) do
    do_search([id: a_number], options)
  end

  defp handle_string_search(str, options) do
    case Integer.parse(str) do
      {num, ""} ->
        do_search([id: "A" <> String.pad_leading(to_string(num), 6, "0")], options)

      # Not an integer, try to parse as a sequence of integers
      _ ->
        case parse_string_to_int_list(str) do
          {:ok, _int_list} ->
            do_search([sequence: str], options)

          {:error, _reason} ->
            do_search([query: str], options)
        end
    end
  end

  defp do_search(terms, options) do
    opts = ensure_options(options)

    case Keyword.fetch(terms, :id) do
      {:ok, id} ->
        case make_id_request(id, opts) do
          {:ok, decoded_json_body} -> handle_oeis_response(decoded_json_body)
          err -> err
        end

      # This is the general search branch

      :error ->
        with {:ok, query_params} <- build_query_string(terms, opts),
             search_url = Path.join(@base_url, "/search"),
             {:ok, decoded_json_body} <- make_request(search_url, query_params, opts) do
          handle_oeis_response(decoded_json_body)
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp make_id_request(id, opts) do
    url = Path.join(@base_url, id)
    make_request(url, [fmt: "json"], opts)
  end

  defp build_query_string(terms, opts) do
    with {:ok, query_map} <- build_base_query_map(terms, opts) do
      start_param = Keyword.get(opts, :start) || Keyword.get(terms, :start)
      handle_start_param(query_map, start_param)
    end
  end

  defp build_base_query_map(terms, opts) do
    do_build_query_terms(terms, opts, {:ok, []})
  end

  defp do_build_query_terms([], _opts, {:ok, acc_terms}) do
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

  defp do_build_query_terms([{_key, nil} | tail], opts, acc_status),
    do: do_build_query_terms(tail, opts, acc_status)

  defp do_build_query_terms([head | tail], opts, {:ok, acc_terms}) do
    {key, value} = head

    case key do
      :start ->
        do_build_query_terms(tail, opts, {:ok, acc_terms})

      _ ->
        case add_query_term(acc_terms, opts, key, value) do
          {:ok, new_acc_terms} ->
            do_build_query_terms(tail, opts, {:ok, new_acc_terms})

          {:error, _} = err ->
            err
        end
    end
  end

  defp do_build_query_terms(_rem, _opts, {:error, _} = err), do: err

  defp handle_start_param(query_map, nil), do: {:ok, query_map}

  defp handle_start_param(query_map, start_param)
       when is_integer(start_param) and start_param >= 0 do
    {:ok, Map.put(query_map, :start, start_param)}
  end

  defp handle_start_param(_query_map, _),
    do: {:error, {:bad_param, ":start must be a non-negative integer."}}

  defp normalize_sequence_to_list(list) when is_list(list) do
    case Enum.all?(list, &is_integer/1) do
      true -> {:ok, list}
      false -> {:error, "Sequence list must contain only integers."}
    end
  end

  defp normalize_sequence_to_list(str) when is_binary(str) do
    case parse_string_to_int_list(str) do
      {:ok, int_list} ->
        case int_list do
          [] -> {:error, "Sequence string cannot be empty."}
          list -> {:ok, list}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_sequence_to_list(_),
    do: {:error, "Sequence must be a list of integers or a string of integers."}

  defp parse_string_to_int_list(str) do
    integers_and_remains =
      str
      |> String.split(~r/[\s,]+/, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&Integer.parse/1)

    case Enum.all?(integers_and_remains, &valid_integer_parse?/1) do
      true ->
        {:ok, Enum.map(integers_and_remains, fn {int, _rest} -> int end)}

      false ->
        {:error, "Sequence string must be a list of integers (comma or space separated)."}
    end
  end

  defp valid_integer_parse?({int, rest}) when is_integer(int) and rest == "", do: true
  defp valid_integer_parse?(_), do: false

  defp add_query_term(acc_terms, opts, :sequence, sequence) do
    case normalize_sequence_to_list(sequence) do
      {:ok, int_list} ->
        final_list =
          case Keyword.get(opts, :may_truncate) do
            true -> truncate_sequence_list(int_list)
            false -> int_list
          end

        prefix =
          case Keyword.get(opts, :respect_sign) do
            true -> "signed:"
            false -> "seq:"
          end

        {:ok, [prefix <> Enum.join(final_list, ",") | acc_terms]}

      {:error, reason} ->
        {:error, {:bad_param, reason}}
    end
  end

  defp add_query_term(acc_terms, _opts, :id, <<"A", _id_num::binary-size(6)>> = id) do
    {:ok, ["id:" <> id | acc_terms]}
  end

  defp add_query_term(_acc_terms, _opts, :id, _id),
    do:
      {:error,
       {:bad_param,
        "ID must be a string starting with 'A' and 7 characters long (e.g., 'A000001')."}}

  defp add_query_term(acc_terms, _opts, key, value)
       when key in @string_fields and is_binary(value) do
    {:ok, ["#{Atom.to_string(key)}:" <> value | acc_terms]}
  end

  defp add_query_term(_acc_terms, _opts, key, _value) when key in @string_fields do
    {:error, {:bad_param, "#{Atom.to_string(key)} must be a string."}}
  end

  defp add_query_term(acc_terms, _opts, :author, author) when is_binary(author) do
    {:ok, ["author:*" <> author <> "*" | acc_terms]}
  end

  defp add_query_term(_acc_terms, _opts, :author, _val),
    do: {:error, {:bad_param, "Author must be a string."}}

  defp add_query_term(acc_terms, _opts, :query, query_str) when is_binary(query_str) do
    {:ok, [query_str | acc_terms]}
  end

  defp add_query_term(_acc_terms, _opts, :query, _val),
    do: {:error, {:bad_param, "General query must be a string."}}

  # Catch-all for unsupported options

  defp add_query_term(_acc_terms, _opts, key, value),
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

  defp make_request(url, query_params, opts) do
    req_opts = [params: query_params, receive_timeout: opts[:timeout]]

    case Req.get(url, req_opts) do
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
    {_ok, data_list} = normalize_sequence_to_list(data)

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

    keyword =
      result
      |> Map.get("keyword", "")
      |> String.split(",", trim: true)

    offset =
      case Map.get(result, "offset", "") |> String.split(",", trim: true) do
        [a, b] -> {String.to_integer(a), String.to_integer(b)}
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
      xref: Map.get(result, "xref"),
      keyword: keyword,
      offset: offset,
      maple: Map.get(result, "maple"),
      mathematica: Map.get(result, "mathematica"),
      program: Map.get(result, "program"),
      revision: Map.get(result, "revision"),
      references: Map.get(result, "references"),
      ext: Map.get(result, "ext"),
      author: extract_author(result),
      created: created,
      time: time
    }
  end

  defp extract_xref_ids(xrefs) do
    case xrefs do
      list when is_list(list) ->
        list
        |> Enum.flat_map(fn text ->
          Regex.scan(~r/A\d{6}/, to_string(text))
        end)
        |> List.flatten()
        |> Enum.uniq()
        |> Enum.sort()

      _ ->
        []
    end
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
      all_texts
      |> Enum.flat_map(fn text ->
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
    href_regex = ~r/href=\"([^\"]*)\">([^<]+)<\/a>/
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
