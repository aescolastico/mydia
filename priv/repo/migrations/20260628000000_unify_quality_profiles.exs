defmodule Mydia.Repo.Migrations.UnifyQualityProfiles do
  use Ecto.Migration

  import Mydia.Repo.Migrations.Helpers

  alias Mydia.Repo.Migrations.QualityProfileBackfill

  def up do
    backfill_preferred_resolutions()
    drop_dead_columns()
  end

  def down do
    raise Ecto.MigrationError,
      message: "unify_quality_profiles is a one-way clean-break migration and cannot be reverted"
  end

  # --- Backfill ---

  defp backfill_preferred_resolutions do
    %{rows: rows} =
      repo().query!("SELECT id, qualities, quality_standards FROM quality_profiles")

    Enum.each(rows, fn [id, qualities_raw, standards_raw] ->
      qualities = decode_list(qualities_raw)
      standards = decode_map(standards_raw)
      new_standards = QualityProfileBackfill.backfilled_standards(qualities, standards)

      if new_standards != standards do
        encoded = Jason.encode!(new_standards)
        {sql, params} = update_sql(encoded, id)
        repo().query!(sql, params)
      end
    end)
  end

  defp update_sql(encoded, id) do
    if postgres?() do
      {"UPDATE quality_profiles SET quality_standards = $1 WHERE id = $2", [encoded, id]}
    else
      {"UPDATE quality_profiles SET quality_standards = ? WHERE id = ?", [encoded, id]}
    end
  end

  defp decode_list(nil), do: []
  defp decode_list(""), do: []

  defp decode_list(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  end

  defp decode_list(list) when is_list(list), do: list
  defp decode_list(_), do: []

  defp decode_map(nil), do: %{}
  defp decode_map(""), do: %{}

  defp decode_map(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp decode_map(map) when is_map(map), do: map
  defp decode_map(_), do: %{}

  # --- Drop columns (adapter-aware) ---

  defp drop_dead_columns do
    if postgres?() do
      execute("ALTER TABLE quality_profiles DROP COLUMN IF EXISTS qualities")
      execute("ALTER TABLE quality_profiles DROP COLUMN IF EXISTS metadata_preferences")
      execute("ALTER TABLE quality_profiles DROP COLUMN IF EXISTS customizations")
    else
      # SQLite: rebuild the table without the three dropped columns.
      recreate_table(
        table: :quality_profiles,
        primary_key: false,
        columns: [
          {:id, :binary_id, [primary_key: true]},
          {:name, :string, [null: false]},
          {:upgrades_allowed, :boolean, [default: true]},
          {:upgrade_until_quality, :string, []},
          {:description, :text, []},
          {:is_system, :boolean, [default: false]},
          {:version, :integer, [default: 1]},
          {:source_url, :string, []},
          {:last_synced_at, :utc_datetime, []},
          {:quality_standards, :text, []}
        ],
        indexes: [
          {[:name], [unique: true]},
          [:is_system],
          [:version]
        ]
      )
    end
  end
end
