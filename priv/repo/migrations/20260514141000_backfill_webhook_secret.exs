defmodule Mydia.Repo.Migrations.BackfillWebhookSecret do
  use Ecto.Migration

  import Ecto.Query

  @moduledoc """
  Backfills `webhook_secret` on `download_client_configs` rows that were
  created before the column existed (added by AddUsenetImprovementColumns,
  20260514113509). Without this backfill, inbound completion webhooks to
  existing SABnzbd/NZBGet clients would return 401 until an admin re-saves
  each client through the UI — surfaced as a P1 finding during code review
  (DM-1, getmydia/mydia#122).

  Generates a 32-byte CSPRNG secret per row via the same mechanism the
  schema changeset uses (`:crypto.strong_rand_bytes/1` |> Base.url_encode64).

  Rollback is a no-op: clearing generated secrets would invalidate webhook
  URLs that operators may have already copied into their notification
  scripts. If a roll-back of the column itself is needed, run the schema
  migration's down step.
  """

  def up do
    ids =
      from(d in "download_client_configs",
        where: is_nil(d.webhook_secret),
        select: d.id
      )
      |> repo().all()

    Enum.each(ids, fn id ->
      secret = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

      from(d in "download_client_configs",
        where: d.id == ^id and is_nil(d.webhook_secret),
        update: [set: [webhook_secret: ^secret]]
      )
      |> repo().update_all([])
    end)
  end

  def down, do: :ok
end
