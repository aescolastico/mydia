defmodule Mydia.Plugins.Log do
  @moduledoc """
  A single per-invocation plugin debug log line (U1).

  Three sources write rows that share one `invocation_id` so the admin detail
  UI can render a unified, chronological timeline per run:

    * `"guest"` — a line the guest emitted via the `log(level, message)` host
      function
    * `"wasi"` — captured WASI stdout/stderr (`println!`, panic text)
    * `"host"` — an invocation/outcome marker emitted by the host
      (`Mydia.Plugins.Host`): start, and the terminal outcome with detail

  Every row carries a `level` (`debug`/`info`/`warn`/`error`) so the detail
  UI's minimum-level filter is uniform across sources — host trap markers are
  `error` level and so always surface under any threshold.

  Logs are immutable (`inserted_at` only) and disposable (retention-capped by
  `Mydia.Jobs.PluginLogCleanup`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @sources [:guest, :wasi, :host]
  @levels [:debug, :info, :warn, :error]

  @type t :: %__MODULE__{
          id: binary() | nil,
          plugin_config_id: binary() | nil,
          slug: String.t(),
          invocation_id: String.t(),
          source: atom(),
          level: atom(),
          message: String.t() | nil,
          metadata: map(),
          test_run: boolean(),
          inserted_at: DateTime.t() | nil
        }

  schema "plugin_logs" do
    field :plugin_config_id, :binary_id
    field :slug, :string
    field :invocation_id, :string
    field :source, Ecto.Enum, values: @sources
    field :level, Ecto.Enum, values: @levels, default: :info
    field :message, :string
    field :metadata, Mydia.Settings.JsonMapType, default: %{}
    field :test_run, :boolean, default: false

    # Microsecond precision so rows written within the same wall-clock second of
    # one invocation (start marker, guest lines, end marker) stay distinguishable
    # and the timeline renders in true insertion order — second precision plus a
    # random binary_id tiebreak scrambles intra-invocation ordering.
    timestamps(inserted_at: :inserted_at, updated_at: false, type: :utc_datetime_usec)
  end

  @doc """
  Changeset for a log row.

  `message` is sanitized to valid UTF-8 (`String.replace_invalid/1`) so
  arbitrary guest stdout/stderr bytes never reach a `:text` column as invalid
  UTF-8 (KTD10 — fails Postgres otherwise).
  """
  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :plugin_config_id,
      :slug,
      :invocation_id,
      :source,
      :level,
      :message,
      :metadata,
      :test_run
    ])
    |> validate_required([:slug, :invocation_id, :source, :level])
    |> sanitize_message()
  end

  # Per-line message cap. The ungated guest `log` fn caps line *count*, not line
  # *size*; this bounds the bytes any single line (guest log or WASI capture)
  # writes to the :text column, mirroring the host-side WASI truncate.
  @max_message_bytes 64 * 1024

  defp sanitize_message(changeset) do
    case get_change(changeset, :message) do
      message when is_binary(message) -> put_change(changeset, :message, clean(message))
      _ -> changeset
    end
  end

  defp clean(message), do: message |> sanitize() |> cap_bytes(@max_message_bytes)

  # binary_part can split a multi-byte char at the cut, so repair the tail.
  defp cap_bytes(string, max) when byte_size(string) > max,
    do: (string |> binary_part(0, max) |> String.replace_invalid()) <> " … [truncated]"

  defp cap_bytes(string, _max), do: string

  @doc "Replaces invalid UTF-8 bytes so the value is safe for a :text column on any engine."
  @spec sanitize(binary()) :: String.t()
  def sanitize(binary) when is_binary(binary), do: String.replace_invalid(binary)

  @doc "Valid log sources."
  def sources, do: @sources

  @doc "Valid log levels, ordered from least to most severe."
  def levels, do: @levels

  @doc """
  Numeric rank of a level for threshold comparisons (debug=0 … error=3).
  Accepts an atom or string.
  """
  @spec level_rank(atom() | String.t()) :: non_neg_integer()
  def level_rank(level) when is_atom(level), do: level_rank(Atom.to_string(level))

  def level_rank(level) when is_binary(level) do
    case level do
      "debug" -> 0
      "info" -> 1
      "warn" -> 2
      "error" -> 3
      _ -> 1
    end
  end
end
