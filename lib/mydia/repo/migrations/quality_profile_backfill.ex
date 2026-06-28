defmodule Mydia.Repo.Migrations.QualityProfileBackfill do
  @moduledoc """
  Pure backfill logic for the UnifyQualityProfiles migration.
  Extracted as a compiled module so the logic can be unit-tested independently
  of the migration script.
  """

  @canonical_resolutions ["360p", "480p", "576p", "720p", "1080p", "2160p", "4320p"]
  @default_resolutions ["360p", "480p", "576p", "720p", "1080p", "2160p"]

  @doc """
  Returns a string-keyed standards map, backfilling `preferred_resolutions`,
  `min_resolution`, and `max_resolution` from the old `qualities` list when
  those keys are absent.

  If `standards` already has a non-empty `preferred_resolutions`, it is
  returned unchanged.
  """
  def backfilled_standards(qualities, standards) do
    standards = standards || %{}
    existing = standards["preferred_resolutions"] || standards[:preferred_resolutions]

    if is_list(existing) and existing != [] do
      standards
    else
      resolutions =
        case qualities do
          list when is_list(list) and list != [] -> list
          _ -> @default_resolutions
        end

      standards
      |> Map.put("preferred_resolutions", resolutions)
      |> maybe_put_resolution_bound("min_resolution", resolutions, &Enum.min_by/2)
      |> maybe_put_resolution_bound("max_resolution", resolutions, &Enum.max_by/2)
    end
  end

  defp maybe_put_resolution_bound(standards, key, _resolutions, _picker)
       when is_map_key(standards, key),
       do: standards

  defp maybe_put_resolution_bound(standards, key, resolutions, picker) do
    ranked = Enum.filter(resolutions, &(&1 in @canonical_resolutions))

    case ranked do
      [] ->
        standards

      list ->
        bound = picker.(list, fn r -> Enum.find_index(@canonical_resolutions, &(&1 == r)) end)
        Map.put(standards, key, bound)
    end
  end
end
