defmodule Mydia.Indexers.ReleaseRanker do
  @moduledoc """
  Ranks and filters torrent search results based on configurable criteria.

  This module provides a pluggable ranking system for selecting the best
  torrent releases from search results. It uses the unified `SearchScorer`
  algorithm to ensure consistent scoring between automatic and manual searches.

  ## Usage

      # Get the best result
      ReleaseRanker.select_best_result(results, min_seeders: 10)

      # Rank all results with scores
      ReleaseRanker.rank_all(results, preferred_qualities: ["1080p", "720p"])

      # Filter by criteria
      ReleaseRanker.filter_acceptable(results, size_range: {500, 10_000})

  ## Scoring Algorithm

  Scoring is handled by `SearchScorer` with the following formula:

      Combined Score = (quality_score * 0.6 + seeder_score + title_bonus) * zero_seeder_penalty

  Where:
  - `quality_score`: 0-100 based on QualityProfile scoring
  - `seeder_score`: log10(seeders + 1) * 10 (max ~30 pts)
  - `title_bonus`: title relevance bonus / 2 (0-10 pts)
  - `zero_seeder_penalty`: 0.7 if seeders == 0, else 1.0

  ## Options

  - `:min_seeders` - Minimum seeder count (default: 0 for Usenet compatibility)
  - `:min_ratio` - Minimum seeder ratio as percentage (default: nil)
  - `:size_range` - `{min_mb, max_mb}` tuple where either can be nil (default: `nil` = no filtering)
  - `:preferred_qualities` - List of resolutions in preference order (for sorting)
  - `:blocked_tags` - List of strings to filter out from titles
  - `:search_query` - Original search query to score title relevance
  - `:quality_profile` - QualityProfile struct for scoring (recommended)
  - `:media_type` - Either `:movie` or `:episode` (default: `nil`, TV filtering only applied when `:movie`)
  - `:expected_title` - Expected show/movie title for pre-ranking title validation. When provided,
    each result is parsed with `ReleaseParser` and rejected if the parsed title has a Jaro distance
    below 0.7 from the expected title. Unparseable releases pass through (fail-open).
    Ignored when `nil` or empty/whitespace-only. (default: `nil`)
  """

  require Logger

  alias Mydia.Downloads.ReleaseValidator
  alias Mydia.Indexers.{SearchResult, SearchScorer}
  alias Mydia.Indexers.Structs.{RankedResult, ScoreBreakdown}
  alias Mydia.Library.ReleaseParser
  alias Mydia.Library.Structs.ParsedFileInfo
  alias Mydia.Settings.QualityProfile

  @type ranked_result :: RankedResult.t()
  @type score_breakdown :: ScoreBreakdown.t()

  @type ranking_options :: [
          min_seeders: non_neg_integer(),
          min_ratio: float() | nil,
          size_range: {non_neg_integer(), non_neg_integer()},
          preferred_qualities: [String.t()],
          preferred_tags: [String.t()],
          blocked_tags: [String.t()],
          search_query: String.t() | nil,
          quality_profile: QualityProfile.t() | nil,
          media_type: :movie | :episode | nil,
          expected_title: String.t() | nil,
          min_post_age_minutes: non_neg_integer() | nil,
          now: DateTime.t() | nil
        ]

  @default_min_seeders 0
  @title_match_threshold 0.7

  @doc """
  Selects the best result from a list based on ranking criteria.

  Returns the result with the highest score along with its score breakdown.
  Returns `nil` if no results pass the filtering criteria.

  ## Examples

      iex> ReleaseRanker.select_best_result(results, min_seeders: 10)
      %{result: %SearchResult{...}, score: 850.5, breakdown: %{...}}

      iex> ReleaseRanker.select_best_result([], [])
      nil
  """
  @spec select_best_result([SearchResult.t()], ranking_options()) :: ranked_result() | nil
  def select_best_result(results, opts \\ []) do
    results
    |> rank_all(opts)
    |> List.first()
  end

  @doc """
  Ranks all results by score in descending order.

  Returns a list of maps containing the result, total score, and score breakdown.
  Results that don't meet filtering criteria are excluded.

  ## Examples

      iex> ReleaseRanker.rank_all(results, preferred_qualities: ["1080p"])
      [
        %{result: %SearchResult{...}, score: 850.5, breakdown: %{quality: 480, seeders: 200, ...}},
        %{result: %SearchResult{...}, score: 720.3, breakdown: %{quality: 400, seeders: 180, ...}}
      ]
  """
  @spec rank_all([SearchResult.t()], ranking_options()) :: [ranked_result()]
  def rank_all(results, opts \\ []) do
    preferred_qualities = Keyword.get(opts, :preferred_qualities)

    Logger.info(
      "[ReleaseRanker] rank_all called with opts: preferred_qualities=#{inspect(preferred_qualities)}, " <>
        "min_seeders=#{inspect(Keyword.get(opts, :min_seeders))}, " <>
        "size_range=#{inspect(Keyword.get(opts, :size_range))}"
    )

    search_query = Keyword.get(opts, :search_query)

    media_type = Keyword.get(opts, :media_type)
    expected_title = Keyword.get(opts, :expected_title)

    ranked =
      results
      |> reject_invalid_releases()
      |> filter_acceptable(opts)
      |> reject_tv_releases_for_movies(media_type)
      |> reject_title_mismatches(expected_title)
      |> Enum.map(fn result ->
        breakdown = calculate_score_breakdown(result, opts)
        RankedResult.new(%{result: result, score: breakdown.total, breakdown: breakdown})
      end)
      |> reject_zero_title_match(search_query)
      |> sort_by_score_and_preferences(preferred_qualities)

    # Log the top 5 results after sorting
    top_5 = Enum.take(ranked, 5)

    Logger.info("[ReleaseRanker] Top 5 results after sorting by preferences:")

    Enum.each(top_5, fn %{result: result, score: score} ->
      resolution = if result.quality, do: result.quality.resolution, else: "unknown"
      quality_idx = quality_preference_index(result, preferred_qualities)

      Logger.info(
        "  - [idx=#{quality_idx}] #{resolution} | score=#{Float.round(score, 1)} | #{String.slice(result.title, 0, 60)}"
      )
    end)

    ranked
  end

  @doc """
  Filters results to only those meeting minimum criteria.

  Removes results that:
  - Have fewer than `:min_seeders` seeders
  - Have seeder ratio below `:min_ratio` (if specified)
  - Fall outside the `:size_range` (in MB)
  - Contain any `:blocked_tags` in their title

  ## Examples

      iex> ReleaseRanker.filter_acceptable(results, min_seeders: 10, blocked_tags: ["CAM"])
      [%SearchResult{...}, ...]

      iex> ReleaseRanker.filter_acceptable(results, min_ratio: 0.15)
      [%SearchResult{...}, ...]
  """
  @spec filter_acceptable([SearchResult.t()], ranking_options()) :: [SearchResult.t()]
  def filter_acceptable(results, opts \\ []) do
    min_seeders = Keyword.get(opts, :min_seeders, @default_min_seeders)
    min_ratio = Keyword.get(opts, :min_ratio)
    size_range = Keyword.get(opts, :size_range)
    blocked_tags = Keyword.get(opts, :blocked_tags, [])
    min_post_age_minutes = Keyword.get(opts, :min_post_age_minutes)
    now = Keyword.get(opts, :now) || DateTime.utc_now()

    Enum.filter(results, fn result ->
      cond do
        not meets_seeder_minimum?(result, min_seeders) ->
          Logger.info(
            "[ReleaseRanker] Filtered out (seeders #{inspect(result.seeders)} < #{min_seeders}): #{result.title}"
          )

          false

        min_ratio != nil and not meets_ratio_minimum?(result, min_ratio) ->
          seeders = result.seeders || 0
          leechers = result.leechers || 0
          total = seeders + leechers
          ratio = if total > 0, do: Float.round(seeders / total * 100, 1), else: 0.0

          Logger.info(
            "[ReleaseRanker] Filtered out (ratio #{ratio}% < #{Float.round(min_ratio * 100, 1)}%): #{result.title}"
          )

          false

        size_range != nil and not within_size_range?(result, size_range) ->
          {min_mb, max_mb} = size_range
          size_mb = Float.round(bytes_to_mb(result.size), 1)
          range_str = format_size_range(min_mb, max_mb)

          Logger.info(
            "[ReleaseRanker] Filtered out (size #{size_mb} MB not in #{range_str}): #{result.title}"
          )

          false

        not not_blocked?(result, blocked_tags) ->
          Logger.info("[ReleaseRanker] Filtered out (blocked tag): #{result.title}")
          false

        not meets_post_age_minimum?(result, min_post_age_minutes, now) ->
          Logger.info(
            "[ReleaseRanker] Filtered out (NZB posted < #{min_post_age_minutes} min ago): #{result.title}"
          )

          false

        true ->
          true
      end
    end)
  end

  ## Private Functions - Filtering

  # NZB results have no seeders concept - the seeder minimum applies only to
  # torrents. nil seeders pass through.
  defp meets_seeder_minimum?(%SearchResult{seeders: nil}, _min_seeders), do: true

  defp meets_seeder_minimum?(%SearchResult{seeders: seeders}, min_seeders) do
    seeders >= min_seeders
  end

  defp meets_ratio_minimum?(_result, nil), do: true

  # NZB results have no ratio concept - skip the ratio check for them.
  defp meets_ratio_minimum?(%SearchResult{seeders: nil}, _min_ratio), do: true

  defp meets_ratio_minimum?(%SearchResult{seeders: seeders, leechers: leechers}, min_ratio) do
    leechers = leechers || 0
    total_peers = seeders + leechers

    if total_peers == 0 do
      # No peers at all - allow it
      true
    else
      seeder_ratio = seeders / total_peers
      seeder_ratio >= min_ratio
    end
  end

  # NZB minimum post-age filter. NZB results posted within `min_post_age_minutes`
  # of `now` are excluded. Torrents and NZB results without a `usenet_date`
  # pass through. nil/0 setting disables the filter.
  defp meets_post_age_minimum?(_result, nil, _now), do: true
  defp meets_post_age_minimum?(_result, 0, _now), do: true

  defp meets_post_age_minimum?(
         %SearchResult{download_protocol: :nzb, usenet_date: %DateTime{} = posted},
         minutes,
         now
       )
       when is_integer(minutes) and minutes > 0 do
    cutoff = DateTime.add(now, -minutes * 60, :second)
    # A result is "too recent" when it was posted strictly after the cutoff.
    # A result exactly at the cutoff (posted == cutoff) is kept.
    DateTime.compare(posted, cutoff) != :gt
  end

  defp meets_post_age_minimum?(_result, _minutes, _now), do: true

  # nil size_range disables size filtering
  defp within_size_range?(_result, nil), do: true

  # Handle partial ranges where min or max might be nil
  defp within_size_range?(%SearchResult{size: size_bytes}, {min_mb, max_mb}) do
    size_mb = bytes_to_mb(size_bytes)

    above_min = min_mb == nil or size_mb >= min_mb
    below_max = max_mb == nil or size_mb <= max_mb

    above_min and below_max
  end

  defp format_size_range(nil, nil), do: "any"
  defp format_size_range(min, nil), do: "#{min}+ MB"
  defp format_size_range(nil, max), do: "0-#{max} MB"
  defp format_size_range(min, max), do: "#{min}-#{max} MB"

  defp not_blocked?(%SearchResult{title: title}, blocked_tags) do
    title_lower = String.downcase(title)

    not Enum.any?(blocked_tags, fn tag ->
      String.contains?(title_lower, String.downcase(tag))
    end)
  end

  ## Scoring Functions

  @doc """
  Calculates the full score breakdown for a single search result.

  Used by both automatic searches and manual UI searches for consistent scoring.
  Returns a `ScoreBreakdown` struct with individual component scores and total.

  This function always uses the unified SearchScorer algorithm to ensure
  consistent scoring between manual and automatic searches.

  ## Options

  Same as `rank_all/2`:
  - `:quality_profile` - QualityProfile struct for scoring (optional, but recommended)
  - `:media_type` - Either `:movie` or `:episode` (default: `:movie`)
  - `:search_query` - Original search query to score title relevance
  - `:preferred_qualities` - List of resolutions in preference order (used for sorting)
  """
  @spec calculate_score_breakdown(SearchResult.t(), ranking_options()) :: ScoreBreakdown.t()
  def calculate_score_breakdown(%SearchResult{} = result, opts) do
    quality_profile = Keyword.get(opts, :quality_profile)
    media_type = Keyword.get(opts, :media_type, :movie)
    search_query = Keyword.get(opts, :search_query)
    preferred_tags = Keyword.get(opts, :preferred_tags, [])

    scorer_opts = [
      quality_profile: quality_profile,
      media_type: media_type,
      search_query: search_query
    ]

    score_result = SearchScorer.score_result_with_breakdown(result, scorer_opts)

    # Extract individual components for the breakdown struct
    breakdown = score_result.breakdown
    quality_score = Map.get(breakdown, :quality_score, 0.0)
    seeder_score = Map.get(breakdown, :seeder_score, 0.0)
    title_bonus = Map.get(breakdown, :title_bonus, 0.0)

    # Calculate tag bonus from preferred_tags
    tag_bonus = calculate_tag_bonus(result.title, preferred_tags)

    size_mb = bytes_to_mb(result.size)
    seeders = result.seeders || 0
    leechers = result.leechers || 0
    total_peers = seeders + leechers
    seeder_ratio = if total_peers > 0, do: seeders / total_peers, else: 0.0

    # Add tag_bonus to total score
    total_score = score_result.score + tag_bonus

    Logger.info("""
    [ReleaseRanker] Score breakdown for: #{result.title}
      Raw values:
        - Size: #{Float.round(size_mb, 1)} MB
        - Seeders: #{inspect(result.seeders)}, Leechers: #{inspect(result.leechers)}
        - Seeder ratio: #{Float.round(seeder_ratio * 100, 1)}%
        - Quality: #{inspect(result.quality)}
      Component scores:
        - Quality:  #{Float.round(quality_score, 2)} (60% weight in combined score)
        - Seeders:  #{Float.round(seeder_score, 2)} (30% weight in combined score)
        - Title:    #{Float.round(title_bonus, 2)} (10% weight in combined score)
        - Tag bonus: #{Float.round(tag_bonus, 2)}
        - Zero-seeder penalty: #{Map.get(breakdown, :zero_seeder_penalty, 1.0)}
      TOTAL: #{Float.round(total_score, 2)}
    """)

    # Map to ScoreBreakdown struct
    ScoreBreakdown.new(%{
      quality: round_score(quality_score),
      seeders: round_score(seeder_score),
      size: 0.0,
      age: 0.0,
      title_match: round_score(title_bonus * 100),
      tag_bonus: round_score(tag_bonus),
      total: round_score(total_score)
    })
  end

  ## Private Functions - Release Validation Filtering

  # Drop releases the ReleaseValidator flags as invalid/fake/malicious before
  # anything else runs. This is the enforcement point for the validator: it only
  # *detects* bad releases, so without this stage a flagged release (e.g. a
  # malware torrent named "...h264-ETHEL.exe") still flows through scoring and
  # can be selected and grabbed. The title-mismatch check below
  # (parse_and_compare/2) parses with ReleaseParser and does not validate, so
  # this stage is the sole validation gate for ranking. Reject here so a
  # suspicious release never reaches a download client.
  defp reject_invalid_releases(results) do
    Enum.filter(results, fn result ->
      case ReleaseValidator.validate_release(result.title) do
        {:ok, _name} ->
          true

        {:error, reason} ->
          Logger.warning(
            "[ReleaseRanker] Filtered out (invalid release: #{reason}): #{result.title}"
          )

          false
      end
    end)
  end

  ## Private Functions - Media Type Filtering

  # When searching for a movie, reject releases that contain TV season/episode
  # patterns (S01, S01E05, etc.) since they're clearly TV content, not movies.
  # This prevents false matches like "Frozen Planet II S01" matching "Frozen 2013".
  @tv_season_pattern ~r/\bS\d{1,2}(?:E\d{1,3})?\b/i

  defp reject_tv_releases_for_movies(results, :movie) do
    Enum.filter(results, fn result ->
      if Regex.match?(@tv_season_pattern, result.title) do
        Logger.info(
          "[ReleaseRanker] Filtered out (TV season/episode pattern in movie search): #{result.title}"
        )

        false
      else
        true
      end
    end)
  end

  defp reject_tv_releases_for_movies(results, _media_type), do: results

  ## Private Functions - Title Mismatch Filtering

  # When an expected_title is provided, parse each result's release name to extract
  # the actual show/movie title, then reject results where the parsed title doesn't
  # match the expected title. This prevents downloading wrong shows when an indexer
  # returns results where the search term appears as an episode title rather than
  # the show title (e.g., "Claws S01E04 Fallout" when searching for "Fallout").
  defp reject_title_mismatches(results, nil), do: results
  defp reject_title_mismatches(results, ""), do: results

  defp reject_title_mismatches(results, expected_title) when is_binary(expected_title) do
    trimmed = String.trim(expected_title)

    if trimmed == "" do
      results
    else
      normalized_expected = normalize_for_comparison(trimmed)

      Enum.filter(results, fn result ->
        case parse_and_compare(result, normalized_expected) do
          {:mismatch, parsed_title, distance} ->
            Logger.info(
              "[ReleaseRanker] Filtered out (title mismatch): " <>
                "parsed='#{parsed_title}' expected='#{trimmed}' " <>
                "distance=#{Float.round(distance, 2)}: #{result.title}"
            )

            false

          _ ->
            true
        end
      end)
    end
  end

  # Parse a result's title and compare against the pre-normalized expected title.
  # Returns {:mismatch, parsed_title, distance} if below threshold, :ok otherwise.
  #
  # Calls ReleaseParser.parse/1 directly (not ReleaseIntake): reject_invalid_releases/1
  # already ran the validator over the full result list upstream, so re-validating
  # here would be a redundant double-pass. The two stages must be maintained
  # together — if the upstream validator filter is removed, this path would need
  # its own validation. A nil/unparseable title falls through to :ok (fail-open).
  defp parse_and_compare(result, normalized_expected) do
    case ReleaseParser.parse(result.title) do
      %ParsedFileInfo{title: parsed_title} when is_binary(parsed_title) ->
        distance =
          String.jaro_distance(normalized_expected, normalize_for_comparison(parsed_title))

        if distance < @title_match_threshold do
          {:mismatch, parsed_title, distance}
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp normalize_for_comparison(title) do
    title
    |> String.downcase()
    |> normalize_unicode()
    |> String.replace("_", " ")
    |> String.replace(~r/[^\w\s]/u, "")
    |> String.replace(~r/\b(the|a|an)\b/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # NFD decomposition strips accents universally: é → e, ñ → n, ç → c, etc.
  # German transliterations (ä→ae, ß→ss) are applied first since NFD would just strip the umlaut.
  defp normalize_unicode(str) do
    str
    |> String.replace("ä", "ae")
    |> String.replace("ö", "oe")
    |> String.replace("ü", "ue")
    |> String.replace("ß", "ss")
    |> then(&:unicode.characters_to_nfd_binary/1)
    |> String.replace(~r/\p{Mn}/u, "")
  end

  ## Private Functions - Title Match Filtering

  # When a search_query is provided, reject results where the title doesn't match
  # the query at all (title_match == 0.0). This prevents downloading completely
  # unrelated content that happens to have high quality/seeder scores.
  defp reject_zero_title_match(ranked_results, nil), do: ranked_results
  defp reject_zero_title_match(ranked_results, ""), do: ranked_results

  defp reject_zero_title_match(ranked_results, _search_query) do
    Enum.filter(ranked_results, fn %{result: result, breakdown: breakdown} ->
      if breakdown.title_match > 0.0 do
        true
      else
        Logger.info("[ReleaseRanker] Filtered out (zero title match): #{result.title}")

        false
      end
    end)
  end

  ## Private Functions - Sorting

  defp sort_by_score_and_preferences(ranked_results, nil) do
    Enum.sort_by(ranked_results, & &1.score, :desc)
  end

  defp sort_by_score_and_preferences(ranked_results, preferred_qualities) do
    ranked_results
    |> Enum.sort_by(fn %{result: result, score: score} ->
      quality_index = quality_preference_index(result, preferred_qualities)
      # Sort by: quality preference (lower index = higher priority), then score
      {quality_index, -score}
    end)
  end

  defp quality_preference_index(%SearchResult{quality: nil}, _preferred_qualities) do
    999
  end

  defp quality_preference_index(_result, nil) do
    # No preferred qualities set, return 0 so all results sort by score only
    0
  end

  defp quality_preference_index(_result, []) do
    # Empty preferred qualities list, return 0 so all results sort by score only
    0
  end

  defp quality_preference_index(%SearchResult{quality: quality}, preferred_qualities) do
    case quality.resolution do
      nil ->
        999

      resolution ->
        case Enum.find_index(preferred_qualities, &(&1 == resolution)) do
          nil -> 999
          index -> index
        end
    end
  end

  @doc """
  Scores all results and returns detailed information about each, including rejection reasons.

  Unlike `rank_all/2`, this function includes ALL results (even those filtered out)
  and provides the reason why each was rejected (if applicable).

  Returns a list of maps containing:
  - `:title` - The release title
  - `:score` - The calculated score (0 if rejected before scoring)
  - `:seeders` - Seeder count
  - `:size_mb` - Size in megabytes
  - `:resolution` - Detected resolution (if available)
  - `:status` - Either `:accepted` or `:rejected`
  - `:rejection_reason` - Why it was rejected (nil if accepted)

  Results are sorted by score descending.

  ## Examples

      iex> ReleaseRanker.score_all_with_reasons(results, min_seeders: 10)
      [
        %{title: "Movie.2024.1080p", score: 75.5, status: :accepted, ...},
        %{title: "Movie.2024.CAM", score: 0, status: :rejected, rejection_reason: "blocked_tag: CAM", ...}
      ]
  """
  @spec score_all_with_reasons([SearchResult.t()], ranking_options()) :: [map()]
  def score_all_with_reasons(results, opts \\ []) do
    min_seeders = Keyword.get(opts, :min_seeders, @default_min_seeders)
    min_ratio = Keyword.get(opts, :min_ratio)
    size_range = Keyword.get(opts, :size_range)
    blocked_tags = Keyword.get(opts, :blocked_tags, [])
    expected_title = Keyword.get(opts, :expected_title)

    results
    |> Enum.map(fn result ->
      size_mb = bytes_to_mb(result.size)
      resolution = if result.quality, do: result.quality.resolution, else: nil

      base_info = %{
        title: result.title,
        seeders: result.seeders,
        size_mb: Float.round(size_mb, 1),
        resolution: resolution
      }

      # Check rejection reasons in order
      rejection =
        get_rejection_reason(
          result,
          min_seeders,
          min_ratio,
          size_range,
          blocked_tags,
          expected_title
        )

      case rejection do
        nil ->
          # Not rejected, calculate score
          breakdown = calculate_score_breakdown(result, opts)

          Map.merge(base_info, %{
            score: breakdown.total,
            status: :accepted,
            rejection_reason: nil,
            breakdown: %{
              quality: breakdown.quality,
              seeders: breakdown.seeders,
              title_match: breakdown.title_match
            }
          })

        reason ->
          Map.merge(base_info, %{
            score: 0.0,
            status: :rejected,
            rejection_reason: reason,
            breakdown: nil
          })
      end
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  # Returns rejection reason string or nil if acceptable
  defp get_rejection_reason(
         result,
         min_seeders,
         min_ratio,
         size_range,
         blocked_tags,
         expected_title
       ) do
    cond do
      not meets_seeder_minimum?(result, min_seeders) ->
        "low_seeders: #{result.seeders} < #{min_seeders}"

      min_ratio != nil and not meets_ratio_minimum?(result, min_ratio) ->
        seeders = result.seeders || 0
        leechers = result.leechers || 0
        total = seeders + leechers
        ratio = if total > 0, do: Float.round(seeders / total * 100, 1), else: 0.0
        "low_ratio: #{ratio}% < #{Float.round(min_ratio * 100, 1)}%"

      size_range != nil and not within_size_range?(result, size_range) ->
        {min_mb, max_mb} = size_range
        size_mb = Float.round(bytes_to_mb(result.size), 1)
        "size_out_of_range: #{size_mb} MB not in #{min_mb}-#{max_mb} MB"

      blocked_tag = find_blocked_tag(result, blocked_tags) ->
        "blocked_tag: #{blocked_tag}"

      expected_title_mismatch?(result, expected_title) ->
        "title_mismatch"

      true ->
        nil
    end
  end

  defp expected_title_mismatch?(_result, nil), do: false
  defp expected_title_mismatch?(_result, ""), do: false

  defp expected_title_mismatch?(result, expected_title) when is_binary(expected_title) do
    trimmed = String.trim(expected_title)

    if trimmed == "" do
      false
    else
      match?({:mismatch, _, _}, parse_and_compare(result, normalize_for_comparison(trimmed)))
    end
  end

  # Find which blocked tag matched (if any)
  defp find_blocked_tag(%SearchResult{title: title}, blocked_tags) do
    title_lower = String.downcase(title)

    Enum.find(blocked_tags, fn tag ->
      String.contains?(title_lower, String.downcase(tag))
    end)
  end

  ## Private Functions - Helpers

  # Calculate bonus points for matching preferred_tags in the title
  # Each matching tag adds 10 points to help preferred releases rank higher
  defp calculate_tag_bonus(_title, []), do: 0.0

  defp calculate_tag_bonus(title, preferred_tags) do
    title_upper = String.upcase(title)

    matching_tags =
      Enum.count(preferred_tags, fn tag ->
        String.contains?(title_upper, String.upcase(tag))
      end)

    # 10 points per matching tag
    matching_tags * 10.0
  end

  defp bytes_to_mb(bytes) when is_integer(bytes) do
    bytes / (1024 * 1024)
  end

  defp round_score(value) when is_float(value), do: Float.round(value, 2)
  defp round_score(value) when is_integer(value), do: value * 1.0
end
