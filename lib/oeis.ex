defmodule OEIS do
  alias Jason
  alias OEIS.Sequence

  @moduledoc """
  A client for the On-Line Encyclopedia of Integer Sequences (OEIS).
  """

  @base_url "https://oeis.org"

  @doc """
  Searches the OEIS database.

  This function is the main entry point for querying the OEIS. It can be called
  with a keyword list of search parameters, a raw list of integers (treated as
  a sequence), or a raw string.

  When called with a string, it will be treated as an OEIS ID if it matches
  the `A` number format (e.g., `"A000055"`), otherwise it will be treated as a
  comma-separated sequence (e.g., `"1,2,3,4"`).

  On success, returns `{:ok, [list_of_sequences]}` where `list_of_sequences`
  is a list of `OEIS.Sequence` structs. If no results are found, it returns
  an empty list: `{:ok, []}`.

  If a query returns a full page of results (currently 10 sequences for general
  searches), it implies there might be more results available. In such cases,
  a `{:partial, message, [list_of_sequences], response_map}` tuple is returned, indicating
  that the query might need refinement or pagination (`:start` option).

  ## Parameters

  When called with a keyword list, the following keys are accepted:

  * `:sequence` (list of integers or a comma-separated string): A list of terms
    in the sequence to search for.
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
      {:ok, [%OEIS.Sequence{id: "A000045", name: "Fibonacci numbers." <> _}]}

      iex> OEIS.search([1, 2, 3, 5, 8])
      {:ok, [%OEIS.Sequence{id: "A000045", name: "Fibonacci numbers." <> _}]}

      iex> OEIS.search(query: "non-existent query")
      {:ok, []}

      iex> OEIS.search(author: "Sloane", keyword: "core", start: 10)
      {:ok, list_of_sequences}

      iex> {:partial, _message, sequences, _response_map} = OEIS.search(sequence: [1, 2, 3])
      iex> length(sequences)
      10

      # A broad query like "prime number" often returns no results from the JSON API,
      # which translates to an empty list `{:ok, []}`. The OEIS JSON API
      # currently does not provide a distinct indicator for "too many results"
      # versus "no results" in its JSON response.
      iex> OEIS.search(query: "prime number")
      {:ok, []}
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
          {:ok, parsed_json_or_nil} -> handle_oeis_response(parsed_json_or_nil)
          err -> err
        end

      # This is the general search branch
      :error ->
        result =
          with {:ok, query_params} <- build_query_string(opts),
               search_url = Path.join(@base_url, "/search"),
               {:ok, parsed_json_or_nil} <- make_request(search_url, query_params) do
            handle_oeis_response(parsed_json_or_nil)
          end

        case result do
          {:ok, _} = ok -> ok
          {:partial, _message, _sequences, _map} = partial -> partial
          {:error, _} = error -> error
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
    terms =
      with terms <- [] do
        terms
        |> add_sequence_term(Keyword.get(opts, :sequence))
        |> add_id_term(Keyword.get(opts, :id))
        |> add_keyword_term(Keyword.get(opts, :keyword))
        |> add_author_term(Keyword.get(opts, :author))
        |> add_general_query_term(Keyword.get(opts, :query))
        |> add_comment_term(Keyword.get(opts, :comment))
        |> add_ref_term(Keyword.get(opts, :ref))
        |> add_link_term(Keyword.get(opts, :link))
        |> add_formula_term(Keyword.get(opts, :formula))
        |> add_example_term(Keyword.get(opts, :example))
        |> add_name_term(Keyword.get(opts, :name))
        |> add_xref_term(Keyword.get(opts, :xref))
      end

    case terms do
      {:error, _} = err ->
        err

      terms when is_list(terms) ->
        if Enum.empty?(terms) do
          {:error,
           {:bad_param,
            "At least one of :sequence, :id, :keyword, :author, or :query must be provided."}}
        else
          q_value = Enum.join(terms, " ")
          {:ok, %{q: q_value, fmt: "json"}}
        end
    end
  end

  defp handle_start_param(query_map, nil), do: {:ok, query_map}

  defp handle_start_param(query_map, start_param)
       when is_integer(start_param) and start_param >= 0 do
    {:ok, Map.put(query_map, :start, start_param)}
  end

  defp handle_start_param(_query_map, _),
    do: {:error, {:bad_param, ":start must be a non-negative integer."}}

  defp add_sequence_term({:error, _} = err, _), do: err
  defp add_sequence_term(terms, nil), do: terms

  defp add_sequence_term(terms, sequence) when is_list(sequence) do
    case Enum.all?(sequence, &is_integer/1) do
      true ->
        [Enum.map_join(sequence, ",", &to_string/1) | terms]

      false ->
        {:error,
         {:bad_param,
          "Sequence must be a list of integers or a comma-separated string of integers."}}
    end
  end

  defp add_sequence_term(terms, sequence) when is_binary(sequence) do
    case parse_integer_string(sequence) do
      {:ok, int_list} -> [Enum.join(int_list, ",") | terms]
      _ -> {:error, {:bad_param, "Sequence string must be a comma-separated list of integers."}}
    end
  end

  defp add_sequence_term(_, _),
    do:
      {:error,
       {:bad_param,
        "Sequence must be a list of integers or a comma-separated string of integers."}}

  defp parse_integer_string(sequence_str) do
    result =
      sequence_str
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&Integer.parse/1)

    if Enum.all?(result, &match?({_val, ""}, &1)) do
      {:ok, Enum.map(result, fn {val, ""} -> val end)}
    else
      {:error, :not_an_integer_list_string}
    end
  end

  defp add_id_term({:error, _} = err, _), do: err
  defp add_id_term(terms, nil), do: terms

  defp add_id_term(terms, <<"A", _id_num::binary-size(6)>> = id) do
    ["id:" <> id | terms]
  end

  defp add_id_term(_terms, _id),
    do:
      {:error,
       {:bad_param,
        "ID must be a string starting with 'A' and 7 characters long (e.g., 'A000001')."}}

  defp add_keyword_term({:error, _} = err, _), do: err
  defp add_keyword_term(terms, nil), do: terms

  defp add_keyword_term(terms, keyword) when is_binary(keyword) do
    ["keyword:" <> keyword | terms]
  end

  defp add_keyword_term(_, _), do: {:error, {:bad_param, "Keyword must be a string."}}

  defp add_author_term({:error, _} = err, _), do: err
  defp add_author_term(terms, nil), do: terms

  defp add_author_term(terms, author) when is_binary(author) do
    ["author:*" <> author <> "*" | terms]
  end

  defp add_author_term(_, _), do: {:error, {:bad_param, "Author must be a string."}}

  defp add_general_query_term({:error, _} = err, _), do: err
  defp add_general_query_term(terms, nil), do: terms

  defp add_general_query_term(terms, query_str) when is_binary(query_str) do
    [query_str | terms]
  end

  defp add_general_query_term(_, _), do: {:error, {:bad_param, "General query must be a string."}}

  defp add_comment_term({:error, _} = err, _), do: err
  defp add_comment_term(terms, nil), do: terms

  defp add_comment_term(terms, comment) when is_binary(comment),
    do: ["comment:" <> comment | terms]

  defp add_comment_term(_, _), do: {:error, {:bad_param, "Comment must be a string."}}

  defp add_ref_term({:error, _} = err, _), do: err
  defp add_ref_term(terms, nil), do: terms
  defp add_ref_term(terms, ref) when is_binary(ref), do: ["ref:" <> ref | terms]
  defp add_ref_term(_, _), do: {:error, {:bad_param, "Ref must be a string."}}

  defp add_link_term({:error, _} = err, _), do: err
  defp add_link_term(terms, nil), do: terms
  defp add_link_term(terms, link) when is_binary(link), do: ["link:" <> link | terms]
  defp add_link_term(_, _), do: {:error, {:bad_param, "Link must be a string."}}

  defp add_formula_term({:error, _} = err, _), do: err
  defp add_formula_term(terms, nil), do: terms

  defp add_formula_term(terms, formula) when is_binary(formula),
    do: ["formula:" <> formula | terms]

  defp add_formula_term(_, _), do: {:error, {:bad_param, "Formula must be a string."}}

  defp add_example_term({:error, _} = err, _), do: err
  defp add_example_term(terms, nil), do: terms

  defp add_example_term(terms, example) when is_binary(example),
    do: ["example:" <> example | terms]

  defp add_example_term(_, _), do: {:error, {:bad_param, "Example must be a string."}}

  defp add_name_term({:error, _} = err, _), do: err
  defp add_name_term(terms, nil), do: terms
  defp add_name_term(terms, name) when is_binary(name), do: ["name:" <> name | terms]
  defp add_name_term(_, _), do: {:error, {:bad_param, "Name must be a string."}}

  defp add_xref_term({:error, _} = err, _), do: err
  defp add_xref_term(terms, nil), do: terms
  defp add_xref_term(terms, xref) when is_binary(xref), do: ["xref:" <> xref | terms]
  defp add_xref_term(_, _), do: {:error, {:bad_param, "Xref must be a string."}}

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

  defp handle_oeis_response(nil), do: {:ok, []}

  # Case for when the OEIS API returns a list of results (general search).
  defp handle_oeis_response(results) when is_list(results) and length(results) == 10 do
    sequences = Enum.map(results, &map_to_sequence/1)

    warning_message =
      "[OEIS] Your query returned a full page of results. More results might be available. Consider refining your query or using the :start option for pagination."

    # Include the raw results if desired
    {:partial, warning_message, sequences, %{"results" => results}}
  end

  defp handle_oeis_response(results) when is_list(results) do
    sequences = Enum.map(results, &map_to_sequence/1)
    {:ok, sequences}
  end

  # Case for when the OEIS API returns a single sequence object (map) for direct A-number lookups.
  defp handle_oeis_response(%{"id" => _} = single_result) do
    {:ok, [map_to_sequence(single_result)]}
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
      if(is_list(comments), do: comments, else: []) ++
        if is_list(references), do: references, else: []

    authors =
      Enum.flat_map(all_texts, fn text ->
        case Regex.run(author_regex, to_string(text)) do
          [_whole, author] -> [String.trim(author)]
          _ -> []
        end
      end)
      |> Enum.uniq()
      |> Enum.sort()

    if Enum.empty?(authors) do
      nil
    else
      Enum.join(authors, ", ")
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
        Enum.map(matches, fn [_, url, text] ->
          %{url: format_full_url(url), text: text}
        end)

      _ ->
        []
    end
  end

  defp format_full_url("/" <> _rest = url), do: "https://oeis.org" <> url
  defp format_full_url(url), do: url
end
