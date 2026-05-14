defmodule Mydia.Downloads.Client.Helpers do
  @moduledoc """
  Shared parsing helpers for download client adapters.

  Each adapter receives client-specific shapes (qBittorrent JSON, Transmission
  RPC, SABnzbd queue items, NZBGet RPC, rTorrent XML-RPC, Blackhole file stat),
  but they all converge on the same `Mydia.Downloads.Structs.DownloadStatus`
  fields. This module owns the size and timestamp conversions so every adapter
  uses identical, well-tested arithmetic.

  State classification stays per-adapter because the state strings differ
  client-to-client; see each adapter's `parse_state/1`.
  """

  # 1 MiB. Matches the convention used by SABnzbd's `mb` field and NZBGet's
  # `FileSizeMB` field (both report mebibytes, not megabytes).
  @bytes_per_mib 1_048_576

  @doc """
  Converts a value expressed in mebibytes (MiB) into bytes.

  Accepts integers, floats, strings (parsed as floats), and `nil`. Returns an
  integer count of bytes; `nil` and unparseable input yield `0`.

  ## Examples

      iex> parse_size_mb_to_bytes(10)
      10_485_760

      iex> parse_size_mb_to_bytes(1.5)
      1_572_864

      iex> parse_size_mb_to_bytes("2.5")
      2_621_440

      iex> parse_size_mb_to_bytes(nil)
      0

      iex> parse_size_mb_to_bytes("not a number")
      0
  """
  @spec parse_size_mb_to_bytes(integer() | float() | String.t() | nil) :: integer()
  def parse_size_mb_to_bytes(value) do
    value
    |> coerce_float()
    |> Kernel.*(@bytes_per_mib)
    |> round()
  end

  @doc """
  Coerces a size value already expressed in bytes into an integer.

  Accepts integers, floats, strings, and `nil`. Returns an integer count of
  bytes; `nil` and unparseable input yield `0`.

  ## Examples

      iex> parse_size_bytes(1_048_576)
      1_048_576

      iex> parse_size_bytes(1024.5)
      1025

      iex> parse_size_bytes("2048")
      2048

      iex> parse_size_bytes(nil)
      0
  """
  @spec parse_size_bytes(integer() | float() | String.t() | nil) :: integer()
  def parse_size_bytes(value) do
    value
    |> coerce_float()
    |> round()
  end

  @doc """
  Parses a Unix epoch timestamp into a `DateTime`.

  Accepts integers, integer-shaped strings, and `nil`. Returns `nil` for `0`,
  negative values, `nil`, and unparseable input.

  ## Examples

      iex> parse_timestamp_unix(1_700_000_000)
      ~U[2023-11-14 22:13:20Z]

      iex> parse_timestamp_unix("1700000000")
      ~U[2023-11-14 22:13:20Z]

      iex> parse_timestamp_unix(0)
      nil

      iex> parse_timestamp_unix(nil)
      nil
  """
  @spec parse_timestamp_unix(integer() | String.t() | nil) :: DateTime.t() | nil
  def parse_timestamp_unix(value) when is_integer(value) and value > 0 do
    case DateTime.from_unix(value) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  def parse_timestamp_unix(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> parse_timestamp_unix(int)
      _ -> nil
    end
  end

  def parse_timestamp_unix(_), do: nil

  @doc """
  Extracts the per-client `priority_profile` map from a client config map.

  Looks at the top-level `:priority_profile` key first, then falls back to
  `[:options, :priority_profile]` for the legacy nested shape. Returns an
  empty map when neither is set, so callers can pass the result straight
  into `Mydia.Downloads.Priority.resolve/3`.
  """
  @spec priority_profile(map()) :: map()
  def priority_profile(config) do
    Map.get(config, :priority_profile) || get_in(config, [:options, :priority_profile]) ||
      %{}
  end

  # Floors strings/numbers to a float; defaults unparseable input to 0.0.
  defp coerce_float(value) when is_float(value), do: value
  defp coerce_float(value) when is_integer(value), do: value * 1.0

  defp coerce_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> 0.0
    end
  end

  defp coerce_float(_), do: 0.0
end
