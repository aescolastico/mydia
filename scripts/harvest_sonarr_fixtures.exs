#!/usr/bin/env elixir
#
# Harvest Sonarr and Radarr ParserTests fixtures into release-parser regression corpora.
#
# Source: https://github.com/Sonarr/Sonarr and https://github.com/Radarr/Radarr,
# both GPL-3.0-only. AGPL-3.0-or-later distribution (mydia) is one-way compatible per GPL §13.
# Upstream attribution is recorded in test/fixtures/release_parser/UPSTREAM_LICENSE.md.
#
# Usage:
#   ./dev mix run scripts/harvest_sonarr_fixtures.exs
#   ./dev mix run scripts/harvest_sonarr_fixtures.exs --target test/fixtures/release_parser
#   ./dev mix run scripts/harvest_sonarr_fixtures.exs --source sonarr --ref <sha>
#
# The script walks `src/NzbDrone.Core.Test/ParserTests/*.cs`, finds each
# `public void method_name(params)` declaration plus its preceding `[TestCase(...)]`
# attribute lines, and emits `(input, %{field => expected, ...})` tuples per case.
#
# Method names that cannot be mapped to a known field set are recorded in the
# exclusion log. The fixture file is a plain Elixir term file consumable via
# `Code.eval_file/1` from the corpus runner.

defmodule HarvestSonarrFixtures do
  @default_target "test/fixtures/release_parser"
  @sonarr_owner_repo "Sonarr/Sonarr"
  @radarr_owner_repo "Radarr/Radarr"
  @parser_tests_path "src/NzbDrone.Core.Test/ParserTests"

  # Map .NET parameter names (case-insensitive) to fixture field atoms.
  # Unknown names cause the whole method to be skipped with an exclusion log entry.
  @param_map %{
    # Inputs (always the first parameter — these get treated as the release-name input)
    "posttitle" => :input,
    "input" => :input,
    "inputname" => :input,
    # `title` is ambiguous: position 0 → input (handled by idx check); position > 0 → expected title
    "title" => :title,
    "releasename" => :input,
    "releasetitle" => :input,
    "filename" => :input,
    "path" => :input,
    # Expected outputs
    "seriestitle" => :title,
    "expectedtitle" => :title,
    "movietitle" => :title,
    "expectedseriestitle" => :title,
    "expectedmovietitle" => :title,
    "seasonnumber" => :season,
    "season" => :season,
    "episodenumber" => :episode,
    "episode" => :episode,
    "episodenumbers" => :episodes,
    "episodes" => :episodes,
    "absoluteepisodenumbers" => :absolute_episodes,
    "absoluteepisodenumber" => :absolute_episode,
    "year" => :year,
    "edition" => :edition,
    "quality" => :quality,
    "resolution" => :resolution,
    "source" => :source,
    "proper" => :proper,
    "real" => :real,
    "version" => :version,
    "releasehash" => :release_hash,
    "releasegroup" => :release_group,
    "expectedreleasegroup" => :release_group,
    "language" => :language,
    "languages" => :languages,
    "hash" => :hash,
    "isspecial" => :is_special,
    "isvalid" => :is_valid,
    "ispossiblespecialepisode" => :is_special,
    "iscompletevideo" => :is_complete,
    "imdb" => :imdb_id,
    "imdbid" => :imdb_id,
    "tmdbid" => :tmdb_id,
    "fullseason" => :full_season,
    "ispartialseason" => :partial_season,
    "isdaily" => :is_daily,
    "isabsolutenumbering" => :is_absolute_numbering,
    "ismultiepisode" => :is_multi_episode,
    "specialabsoluteepisodenumbers" => :special_absolute_episodes,
    "subgroup" => :release_group,
    "expectedlanguage" => :language,
    "expectedtags" => :language_tags,
    "languagetags" => :language_tags,
    "expected" => :expected,
    "isrepack" => :repack,
    "airdate" => :airdate,
    "month" => :month,
    "day" => :day,
    "part" => :part,
    "reality" => :reality,
    "seasonpart" => :season_part,
    "seriesname" => :title,
    "specialepisodenumber" => :special_episode,
    "firstseason" => :first_season,
    "clean" => :cleaned,
    "titles" => :titles,
    "titlewithoutyear" => :title_without_year
  }

  def run(argv) do
    {opts, _} =
      OptionParser.parse!(argv,
        strict: [
          target: :string,
          sonarr_ref: :string,
          radarr_ref: :string,
          source: :string,
          skip_sonarr: :boolean,
          skip_radarr: :boolean
        ]
      )

    target = Path.expand(opts[:target] || @default_target)
    File.mkdir_p!(target)

    cond do
      opts[:source] == "sonarr" ->
        harvest(:sonarr, target, opts)

      opts[:source] == "radarr" ->
        harvest(:radarr, target, opts)

      true ->
        unless opts[:skip_sonarr], do: harvest(:sonarr, target, opts)
        unless opts[:skip_radarr], do: harvest(:radarr, target, opts)
    end
  end

  defp harvest(which, target, opts) do
    {owner_repo, ref_opt, default_branch} =
      case which do
        :sonarr -> {@sonarr_owner_repo, :sonarr_ref, "develop"}
        :radarr -> {@radarr_owner_repo, :radarr_ref, "develop"}
      end

    ref = opts[ref_opt] || resolve_ref(owner_repo, default_branch)
    IO.puts("\nHarvesting #{owner_repo} @ #{ref}")

    files = list_parser_tests(owner_repo, ref)
    IO.puts("  Found #{length(files)} ParserTests/*.cs files")

    {entries, exclusions} =
      Enum.reduce(files, {[], []}, fn file, {entries_acc, excl_acc} ->
        content = fetch_raw(owner_repo, ref, "#{@parser_tests_path}/#{file}")
        IO.write("  #{file}: ")
        {file_entries, file_exclusions} = parse_file(file, content)
        IO.puts("#{length(file_entries)} cases, #{length(file_exclusions)} skipped methods")
        {entries_acc ++ file_entries, excl_acc ++ file_exclusions}
      end)

    name =
      case which do
        :sonarr -> "sonarr_corpus.exs"
        :radarr -> "radarr_corpus.exs"
      end

    out_path = Path.join(target, name)
    write_fixture(out_path, owner_repo, ref, entries, exclusions)
    IO.puts("\n  Wrote #{out_path}")
    IO.puts("    #{length(entries)} test cases harvested")
    IO.puts("    #{length(exclusions)} methods skipped (see :exclusions in file)")
  end

  defp resolve_ref(owner_repo, branch) do
    url = "https://api.github.com/repos/#{owner_repo}/branches/#{branch}"

    case Req.get(url, headers: github_headers()) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        body["commit"]["sha"]

      other ->
        raise "Could not resolve #{owner_repo}@#{branch}: #{inspect(other)}"
    end
  end

  defp list_parser_tests(owner_repo, ref) do
    url = "https://api.github.com/repos/#{owner_repo}/contents/#{@parser_tests_path}?ref=#{ref}"

    case Req.get(url, headers: github_headers()) do
      {:ok, %Req.Response{status: 200, body: entries}} when is_list(entries) ->
        entries
        |> Enum.filter(fn e -> e["type"] == "file" and String.ends_with?(e["name"], ".cs") end)
        |> Enum.map(& &1["name"])
        |> Enum.sort()

      other ->
        raise "Could not list #{owner_repo}/#{@parser_tests_path}@#{ref}: #{inspect(other)}"
    end
  end

  defp fetch_raw(owner_repo, ref, path) do
    url = "https://raw.githubusercontent.com/#{owner_repo}/#{ref}/#{path}"

    case Req.get(url) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) -> body
      other -> raise "Could not fetch #{url}: #{inspect(other)}"
    end
  end

  defp github_headers do
    case System.get_env("GITHUB_TOKEN") do
      nil -> [{"User-Agent", "mydia-release-parser-harvest"}]
      tok -> [{"User-Agent", "mydia-release-parser-harvest"}, {"Authorization", "Bearer #{tok}"}]
    end
  end

  # ---- File parsing ----

  # State machine: walk lines, accumulate TestCase attribute argument-tuples,
  # and on each `public void method(...)` declaration, flush pending cases as the
  # method's cases. Returns {entries, exclusions}.
  @doc false
  def parse_file(file_name, content) do
    lines = String.split(content, "\n")

    {entries, exclusions, _pending} =
      Enum.reduce(lines, {[], [], []}, fn line, {ents, excls, pending} ->
        trimmed = String.trim(line)

        cond do
          # Comment line — ignore
          String.starts_with?(trimmed, "//") ->
            {ents, excls, pending}

          # Start of a TestCase attribute
          starts_test_case?(trimmed) ->
            args_string = extract_test_case_args(trimmed)

            case parse_test_case_args(args_string) do
              {:ok, args} -> {ents, excls, [args | pending]}
              :error -> {ents, [{file_name, :unparseable_test_case, trimmed} | excls], pending}
            end

          # Method declaration — flush pending cases against this method
          method_decl = parse_method_decl(trimmed) ->
            {method_name, params} = method_decl
            pending_cases = Enum.reverse(pending)

            case map_method_to_fields(params) do
              {:ok, field_names} ->
                new_entries =
                  Enum.flat_map(pending_cases, fn args ->
                    case build_entry(args, field_names) do
                      {:ok, entry} ->
                        [Map.put(entry, :source_method, "#{file_name}::#{method_name}") | []]

                      :error ->
                        []
                    end
                  end)

                {new_entries ++ ents, excls, []}

              {:error, reason} ->
                excl = {file_name, method_name, reason}
                {ents, [excl | excls], []}
            end

          # Anything else — keep pending state intact
          true ->
            {ents, excls, pending}
        end
      end)

    {Enum.reverse(entries), Enum.reverse(exclusions)}
  end

  defp starts_test_case?(trimmed) do
    String.starts_with?(trimmed, "[TestCase(") or
      String.starts_with?(trimmed, "[TestCase ")
  end

  # Extracts the inside of `[TestCase(...)]` — returns just the argument string
  # (without the surrounding bracket/paren or trailing `)]`).
  # Assumes the attribute is on a single line, which is the dominant Sonarr style.
  # Strips NUnit's `Description = "..."` named argument since it's test metadata, not data.
  defp extract_test_case_args(line) do
    case Regex.run(~r/^\[TestCase\((.*)\)\s*\]\s*$/, line) do
      [_, inner] ->
        inner
        |> String.replace(~r/,\s*Description\s*=\s*"(?:[^"\\]|\\.)*"\s*$/, "")
        |> String.replace(~r/,\s*Description\s*=\s*@"(?:[^"]|"")*"\s*$/, "")

      _ ->
        nil
    end
  end

  # Parses C# argument syntax: comma-separated values that may be
  # double-quoted strings ("foo"), verbatim strings (@"foo"), integers, booleans,
  # or `null`. Returns a list of typed Elixir values.
  defp parse_test_case_args(nil), do: :error

  defp parse_test_case_args(s) do
    case do_parse_args(s, []) do
      {:ok, args} -> {:ok, args}
      :error -> :error
    end
  end

  defp do_parse_args("", acc), do: {:ok, Enum.reverse(acc)}

  defp do_parse_args(s, acc) do
    s = String.trim_leading(s)

    cond do
      s == "" ->
        {:ok, Enum.reverse(acc)}

      String.starts_with?(s, "@\"") ->
        case scan_verbatim_string(s) do
          {:ok, value, rest} -> after_value(rest, [value | acc])
          :error -> :error
        end

      String.starts_with?(s, "\"") ->
        case scan_regular_string(s) do
          {:ok, value, rest} -> after_value(rest, [value | acc])
          :error -> :error
        end

      starts_array?(s) ->
        case scan_array(s) do
          {:ok, value, rest} -> after_value(rest, [value | acc])
          :error -> :error
        end

      true ->
        case scan_bareword(s) do
          {:ok, value, rest} -> after_value(rest, [value | acc])
          :error -> :error
        end
    end
  end

  defp starts_array?(s) do
    String.match?(s, ~r/^new\s*(?:int|string)?\s*\[\d*\]/)
  end

  # Scans `new[] { 1, 2, 3 }`, `new int[] { ... }`, or `new string[0]` → list
  defp scan_array(s) do
    cond do
      # Empty sized array: `new string[0]` or `new int[0]`
      result = Regex.run(~r/^new\s+(?:int|string)\[\d+\](.*)/s, s) ->
        [_, rest] = result
        {:ok, [], rest}

      result = Regex.run(~r/^new\s*(?:\[\]|int\[\]|string\[\])\s*\{([^}]*)\}(.*)/s, s) ->
        [_, body, rest] = result

        case do_parse_args(String.trim(body), []) do
          {:ok, items} -> {:ok, items, rest}
          :error -> :error
        end

      true ->
        :error
    end
  end

  defp after_value(rest, acc) do
    rest = String.trim_leading(rest)

    cond do
      rest == "" -> {:ok, Enum.reverse(acc)}
      String.starts_with?(rest, ",") -> do_parse_args(String.slice(rest, 1..-1//1), acc)
      true -> :error
    end
  end

  # Regular string: "..." where "" inside is unsupported (uncommon in Sonarr tests)
  # and backslash escapes follow C# rules ("\\" → "\", "\"" → "\"", etc.)
  defp scan_regular_string("\"" <> rest), do: scan_regular_string_body(rest, [])
  defp scan_regular_string(_), do: :error

  defp scan_regular_string_body("\"" <> rest, acc),
    do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp scan_regular_string_body("\\\\" <> rest, acc),
    do: scan_regular_string_body(rest, ["\\" | acc])

  defp scan_regular_string_body("\\\"" <> rest, acc),
    do: scan_regular_string_body(rest, ["\"" | acc])

  defp scan_regular_string_body("\\n" <> rest, acc),
    do: scan_regular_string_body(rest, ["\n" | acc])

  defp scan_regular_string_body("\\t" <> rest, acc),
    do: scan_regular_string_body(rest, ["\t" | acc])

  defp scan_regular_string_body("\\r" <> rest, acc),
    do: scan_regular_string_body(rest, ["\r" | acc])

  defp scan_regular_string_body("", _acc), do: :error

  defp scan_regular_string_body(<<ch::utf8, rest::binary>>, acc),
    do: scan_regular_string_body(rest, [<<ch::utf8>> | acc])

  # Verbatim string: @"..." where "" → "
  defp scan_verbatim_string("@\"" <> rest), do: scan_verbatim_string_body(rest, [])
  defp scan_verbatim_string(_), do: :error

  defp scan_verbatim_string_body("\"\"" <> rest, acc),
    do: scan_verbatim_string_body(rest, ["\"" | acc])

  defp scan_verbatim_string_body("\"" <> rest, acc),
    do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp scan_verbatim_string_body("", _acc), do: :error

  defp scan_verbatim_string_body(<<ch::utf8, rest::binary>>, acc),
    do: scan_verbatim_string_body(rest, [<<ch::utf8>> | acc])

  # Bareword: integer, decimal, boolean, null, or unrecognized C# identifier
  defp scan_bareword(s) do
    cond do
      # Decimal float — match before integer
      result = Regex.run(~r/^(-?\d+\.\d+)(.*)/s, s) ->
        [_, word, rest] = result
        {:ok, String.to_float(word), rest}

      result = Regex.run(~r/^([A-Za-z_][A-Za-z0-9_\.]*|-?\d+)(.*)/s, s) ->
        [_, word, rest] = result

        value =
          case word do
            "true" ->
              true

            "false" ->
              false

            "null" ->
              nil

            _ ->
              cond do
                String.match?(word, ~r/^-?\d+$/) -> String.to_integer(word)
                # Quality enum value like "Quality.HDTV720p" — keep as string sentinel
                true -> {:identifier, word}
              end
          end

        {:ok, value, rest}

      true ->
        :error
    end
  end

  # Parse `public void method_name(type1 param1, type2 param2, ...)`
  defp parse_method_decl(line) do
    case Regex.run(~r/public\s+void\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)/, line) do
      [_, name, params_str] ->
        params = parse_params(params_str)
        {name, params}

      _ ->
        nil
    end
  end

  # Returns [{type, name}, ...] from "string postTitle, int seasonNumber"
  defp parse_params(""), do: []

  defp parse_params(s) do
    s
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn param ->
      case String.split(param, ~r/\s+/) do
        [type, name] -> {type, name}
        [type1, type2, name] -> {"#{type1} #{type2}", name}
        _ -> {nil, nil}
      end
    end)
  end

  # Given parsed params, return {:ok, [field_name | ...]} or {:error, reason}.
  # The first parameter is treated as the input (release name). Later params
  # map to fixture fields via @param_map.
  defp map_method_to_fields([]), do: {:error, :no_params}

  defp map_method_to_fields([{_type, _name} | _] = params) do
    fields =
      params
      |> Enum.with_index()
      |> Enum.map(fn {{_type, name}, idx} ->
        key = name |> to_string() |> String.downcase()

        cond do
          idx == 0 -> :input
          mapped = Map.get(@param_map, key) -> mapped
          true -> {:unknown, name}
        end
      end)

    unknowns = Enum.filter(fields, &match?({:unknown, _}, &1))

    if unknowns == [] do
      {:ok, fields}
    else
      {:error, {:unknown_params, Enum.map(unknowns, fn {:unknown, n} -> n end)}}
    end
  end

  # Pair a TestCase's positional values with the method's field names. The first
  # value is the input string. Drop entries whose input isn't a string.
  defp build_entry(args, fields) do
    cond do
      length(args) != length(fields) ->
        :error

      not is_binary(hd(args)) ->
        :error

      true ->
        {input, expected} =
          Enum.zip(args, fields)
          |> Enum.reduce({nil, %{}}, fn
            {v, :input}, {_, e} -> {v, e}
            {v, field}, {i, e} -> {i, Map.put(e, field, normalize_value(v))}
          end)

        if is_binary(input), do: {:ok, %{input: input, expected: expected}}, else: :error
    end
  end

  defp normalize_value({:identifier, ident}), do: ident
  defp normalize_value(v), do: v

  # ---- Fixture file emission ----

  defp write_fixture(path, source, ref, entries, exclusions) do
    header =
      """
      # Generated by scripts/harvest_sonarr_fixtures.exs.
      # Do not edit by hand — re-run the harvester to refresh.
      #
      # Upstream source: https://github.com/#{source}
      # Upstream license: GPL-3.0-only (one-way compatible with AGPL-3.0-or-later per GPL §13)
      # See test/fixtures/release_parser/UPSTREAM_LICENSE.md for attribution.
      """

    payload =
      """
      %{
        source: "https://github.com/#{source}",
        source_ref: "#{ref}",
        harvested_at: "#{DateTime.utc_now() |> DateTime.to_iso8601()}",
        cases: #{inspect(entries, limit: :infinity, printable_limit: :infinity)},
        exclusions: #{inspect(exclusions, limit: :infinity, printable_limit: :infinity)}
      }
      """

    formatted = payload |> Code.format_string!() |> IO.iodata_to_binary()
    File.write!(path, header <> "\n" <> formatted <> "\n")
  end
end

if System.get_env("MYDIA_HARVEST_AUTORUN") != "false" do
  HarvestSonarrFixtures.run(System.argv())
end
